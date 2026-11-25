# frozen_string_literal: true

class CompanyOnboardingController < ApplicationController
  layout 'landing'

  before_action :require_leader!
  before_action :set_company_and_user

  def show
    if @company.onboarding_completed? && params[:preview].blank?
      redirect_to authenticated_root_path and return
    end

    @business_types = Companies::BusinessProfiles::BUSINESS_TYPES
    @packages = AppModule.packages
    @modules = AppModule.all
    @payment_methods = @company.payment_methods
    @pricing_breakdown = @company.pricing_breakdown
  end

  def update
    ActiveRecord::Base.transaction do
      apply_step_1_business_type!
      apply_step_2_identity!
      apply_step_3_contact_and_social!
      apply_step_4_payment_methods!
      apply_step_5_plan_and_starter_data!

      @company.onboarding_completed = true
      @company.save!
    end

    create_onboarding_completed_notification!

    redirect_to authenticated_root_path,
                notice: "🎉 ¡Listo, #{current_user.display_name}! #{@company.name} quedó configurado con tus 30 días de prueba gratis."
  rescue ActiveRecord::RecordInvalid => e
    @business_types = Companies::BusinessProfiles::BUSINESS_TYPES
    @packages = AppModule.packages
    @modules = AppModule.all
    @payment_methods = @company.payment_methods
    @pricing_breakdown = @company.pricing_breakdown
    flash.now[:alert] = "Por favor revisa los datos ingresados: #{e.message}"
    render :show, status: :unprocessable_entity
  end

  def skip
    @company.update!(onboarding_completed: true)
    redirect_to authenticated_root_path,
                notice: "✨ Configuración omitida. Puedes personalizar tu empresa, métodos de pago y módulos cuando quieras."
  end

  private

  def set_company_and_user
    @company = current_company
    @user = current_user
  end

  def onboarding_params
    params.fetch(:onboarding, {}).permit(
      :business_type,
      :company_name,
      :tagline,
      :leader_name,
      :leader_specialty,
      :whatsapp_number,
      :contact_email,
      :instagram_url,
      :plan_tier,
      :seed_starter_data,
      :pago_movil_bank,
      :pago_movil_id_number,
      :pago_movil_phone,
      :zelle_email,
      :zelle_holder_name,
      :binance_pay_id,
      :binance_email,
      :exchange_rate_mode,
      modules: {}
    )
  end

  def apply_step_1_business_type!
    bt = onboarding_params[:business_type].to_s
    if Companies::BusinessProfiles::BUSINESS_TYPES.key?(bt)
      @company.business_type = bt
    end
  end

  def apply_step_2_identity!
    new_name = onboarding_params[:company_name].to_s.strip
    if new_name.present? && new_name != @company.name
      @company.name = new_name
      @company.slug = @company.unique_slug_for(new_name)
    end

    @company.tagline = onboarding_params[:tagline].to_s.strip if onboarding_params.key?(:tagline)

    user_updates = {}
    leader_name = onboarding_params[:leader_name].to_s.strip
    user_updates[:name] = leader_name if leader_name.present?
    if onboarding_params.key?(:leader_specialty)
      user_updates[:specialty] = onboarding_params[:leader_specialty].to_s.strip
    end
    @user.update!(user_updates) if user_updates.any?
  end

  def apply_step_3_contact_and_social!
    wa = onboarding_params[:whatsapp_number].to_s.strip
    if wa.present?
      @company.whatsapp_number = wa
      @company.contact_phone = wa if @company.contact_phone.blank?
      @user.update!(phone: wa) if @user.phone.blank?
    end

    contact_mail = onboarding_params[:contact_email].to_s.strip
    @company.contact_email = contact_mail.presence || @company.contact_email.presence || @user.email

    ig = onboarding_params[:instagram_url].to_s.strip
    if ig.present?
      # Aceptar @usuario o URL completa
      if !ig.start_with?('http://', 'https://')
        handle = ig.delete_prefix('@')
        ig = "https://instagram.com/#{handle}"
      end
      @company.instagram_url = ig
    end
  end

  def apply_step_4_payment_methods!
    cfg = @company.payment_methods.deep_dup

    pm_phone = onboarding_params[:pago_movil_phone].to_s.strip
    pm_id = onboarding_params[:pago_movil_id_number].to_s.strip
    pm_bank = onboarding_params[:pago_movil_bank].to_s.strip
    if pm_phone.present? || pm_id.present? || pm_bank.present?
      cfg["pago_movil"]["enabled"] = true
      cfg["pago_movil"]["phone"] = pm_phone if pm_phone.present?
      cfg["pago_movil"]["id_number"] = pm_id if pm_id.present?
      cfg["pago_movil"]["bank"] = pm_bank if pm_bank.present?
      cfg["pago_movil"]["holder_name"] = @company.name if cfg["pago_movil"]["holder_name"].blank?
    end

    zelle_email = onboarding_params[:zelle_email].to_s.strip
    zelle_holder = onboarding_params[:zelle_holder_name].to_s.strip
    if zelle_email.present? || zelle_holder.present?
      cfg["zelle"]["enabled"] = true
      cfg["zelle"]["email"] = zelle_email if zelle_email.present?
      cfg["zelle"]["holder_name"] = zelle_holder if zelle_holder.present?
    end

    binance_id = onboarding_params[:binance_pay_id].to_s.strip
    binance_email = onboarding_params[:binance_email].to_s.strip
    if binance_id.present? || binance_email.present?
      cfg["binance"]["enabled"] = true
      cfg["binance"]["pay_id"] = binance_id if binance_id.present?
      cfg["binance"]["email"] = binance_email if binance_email.present?
    end

    rate_mode = onboarding_params[:exchange_rate_mode].to_s.presence
    if rate_mode.in?(%w[auto_bcv custom hidden])
      cfg["exchange_rate"]["mode"] = rate_mode
    end

    @company.payment_methods_config = cfg
  end

  def apply_step_5_plan_and_starter_data!
    chosen_tier = onboarding_params[:plan_tier].to_s.strip
    if Company::VALID_PLAN_TIERS.include?(chosen_tier)
      @company.plan_tier = chosen_tier
      if chosen_tier == 'personalizado' && params.dig(:onboarding, :modules).present?
        formatted = {}
        AppModule.keys.each do |key|
          val = params[:onboarding][:modules][key]
          formatted[key] = (val == "1" || val == true || val == "true")
        end
        @company.enabled_modules = formatted
      elsif chosen_tier != 'personalizado'
        pkg_mods = AppModule.modules_for_package(chosen_tier)
        @company.enabled_modules = AppModule.build_modules_hash(pkg_mods) if pkg_mods.present?
      end
    end

    @company.save! if @company.changed?

    if onboarding_params[:seed_starter_data] == "1"
      @company.seed_starter_catalog!
    end
  end

  def create_onboarding_completed_notification!
    AppNotification.create!(
      company: @company,
      recipient: @user,
      target_area: 'leaders',
      notification_type: 'general',
      title: "🚀 ¡Bienvenido a GigManager, #{@company.name}!",
      message: "Tu prueba gratuita de 30 días (#{@company.plan_tier_name}) está configurada y lista. Invita a tu equipo o registra tu primer evento.",
      action_url: "/gigs"
    )
  rescue StandardError => e
    Rails.logger.warn("[CompanyOnboardingController] notification skipped: #{e.message}")
  end
end
