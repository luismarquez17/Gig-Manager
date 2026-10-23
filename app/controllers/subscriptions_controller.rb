class SubscriptionsController < ApplicationController
  before_action :require_leader!
  skip_before_action :check_company_subscription!, only: [:index, :checkout, :portal, :report_payment, :modules, :update_modules, :calculator, :change_plan, :cancel_scheduled_plan]

  def index
    @company = current_company
    @trial_days_left = @company.days_left_in_trial
    @trial_active = @company.trial_active?
    @trial_expired = @company.trial_expired?
    @active_subscription = @company.active_subscription?
    @pending_payments = @company.subscription_payments.where(status: 'pending').order(created_at: :desc)
    @pricing_breakdown = @company.pricing_breakdown
    @has_scheduled_change = @company.has_scheduled_plan_change?
    @scheduled_pricing = @company.scheduled_pricing_breakdown if @has_scheduled_change
  end

  def modules
    redirect_to subscriptions_path(anchor: 'gigmanager-modules-section')
  end

  def calculator
    redirect_to subscriptions_path(anchor: 'gigmanager-modules-section')
  end

  def update_modules
    @company = current_company
    if params[:modules].present?
      target_tier = params[:plan_tier].presence || @company.effective_plan_tier
      if @company.subscription_paid_and_active?
        @company.schedule_plan_change!(target_tier, params[:modules], @company.trial_ends_at)
        redirect_to subscriptions_path(anchor: 'gigmanager-modules-section'),
                    notice: "Su plan ha sido cambiado exitosamente los cambios se aplicaran a partir del próximo mes disfrute de gig manager."
      else
        @company.update_modules!(params[:modules])
        redirect_to subscriptions_path(anchor: 'gigmanager-modules-section'),
                    notice: "✅ Módulos actualizados con éxito. Tu menú lateral y cuota se han ajustado. ¡Disfruta de Gig Manager!"
      end
    else
      redirect_to subscriptions_path(anchor: 'gigmanager-modules-section'), alert: "No se recibieron parámetros de módulos."
    end
  end

  def change_plan
    @company = current_company
    target_tier = params[:plan_tier].presence || @company.effective_plan_tier
    clean_tier = Company::VALID_PLAN_TIERS.include?(target_tier.to_s) ? target_tier.to_s : 'banda'

    # Construir hash de módulos seleccionados
    modules_hash = if params[:modules].present?
                     params[:modules]
                   else
                     pkg_mods = AppModule.modules_for_package(clean_tier)
                     AppModule.keys.each_with_object({}) { |k, h| h[k] = pkg_mods.include?(k) }
                   end

    if @company.subscription_paid_and_active?
      timing = params[:timing].presence || 'next_cycle'
      effective_date = @company.trial_ends_at || 30.days.from_now

      if timing == 'immediate' && params[:pay_difference] == '1'
        diff_amount = params[:difference_amount].to_f
        redirect_to subscriptions_path(
          anchor: 'reportar-pago',
          plan_tier: clean_tier,
          amount: diff_amount,
          notes: "Pago de diferencia para activación inmediata de #{AppModule.package_info(clean_tier)&.dig(:name) || clean_tier}"
        ), notice: "Reporta el pago de la diferencia ($#{'%.2f' % diff_amount} USD) para activar tu mejora de plan de inmediato."
        return
      end

      # Programar cambio para el próximo ciclo
      @company.schedule_plan_change!(clean_tier, modules_hash, effective_date)

      # Notificación interna persistente en el buzón
      plan_display = @company.scheduled_plan_name
      date_display = (I18n.l(effective_date.to_date, format: :long) rescue effective_date.strftime('%d/%m/%Y'))

      begin
        AppNotification.create!(
          company: @company,
          sender: current_user,
          target_area: 'leaders',
          notification_type: 'general',
          title: "📅 Cambio de Plan Programado para el Próximo Mes",
          message: "Tu cambio al #{plan_display} ha sido programado con éxito. Se aplicará a partir del #{date_display}. Hasta esa fecha sigues disfrutando de tu plan actual.",
          action_url: "/subscriptions"
        )
      rescue => _e
        # Notificación opcional
      end

      redirect_to subscriptions_path(anchor: 'gigmanager-modules-section'),
                  notice: "Su plan ha sido cambiado exitosamente los cambios se aplicaran a partir del próximo mes disfrute de gig manager."
    else
      # Antes de pagar el mes (en prueba gratuita, pago vencido o pendiente)
      @company.update_modules!(modules_hash)
      @company.update!(plan_tier: clean_tier)
      @company.cancel_scheduled_plan_change! if @company.has_scheduled_plan_change?

      fee = @company.calculated_monthly_fee
      plan_display = @company.plan_tier_name
      redirect_to subscriptions_path(anchor: 'gigmanager-modules-section'),
                  notice: "✅ Tu plan ha sido seleccionado exitosamente como #{plan_display} ($#{'%.2f' % fee} USD/mes). Este será el monto de tu mensualidad. ¡Disfruta de Gig Manager!"
    end
  end

  def cancel_scheduled_plan
    @company = current_company
    if @company.has_scheduled_plan_change?
      current_name = @company.plan_tier_name
      @company.cancel_scheduled_plan_change!
      redirect_to subscriptions_path(anchor: 'gigmanager-modules-section'),
                  notice: "✅ El cambio de plan programado ha sido cancelado. Continuarás con tu #{current_name} actual sin variaciones."
    else
      redirect_to subscriptions_path(anchor: 'gigmanager-modules-section'),
                  alert: "No tienes ningún cambio de plan programado actualmente."
    end
  end

  def report_payment
    @company = current_company
    default_tier = if @company.has_scheduled_plan_change?
                     @company.scheduled_plan_tier
                   else
                     @company.effective_plan_tier
                   end

    plan_tier = params[:plan_tier].presence || default_tier

    amount = if params[:amount].present? && params[:amount].to_f > 0
               params[:amount].to_f
             elsif @company.has_scheduled_plan_change? && plan_tier == @company.scheduled_plan_tier
               @company.scheduled_monthly_fee
             elsif plan_tier == 'personalizado'
               AppModule.calculate_pricing('personalizado', @company.enabled_module_keys)[:total_price]
             else
               AppModule.package_info(plan_tier)&.dig(:price) || 15.00
             end

    @payment = @company.subscription_payments.build(
      user: current_user,
      plan_tier: plan_tier,
      payment_method: params[:payment_method],
      reference_number: params[:reference_number].to_s.strip,
      amount: amount,
      notes: params[:notes]
    )

    if @payment.save
      redirect_to subscriptions_path, notice: "🎉 ¡Pago reportado con éxito! Referencia ##{@payment.reference_number}. Tu suscripción será verificada y activada en breve."
    else
      redirect_to subscriptions_path, alert: "⚠️ No se pudo reportar el pago: #{@payment.errors.full_messages.to_sentence}"
    end
  end

  def checkout
    plan_tier = params[:plan_tier] == 'pro' ? 'pro' : 'starter'
    price_amount = plan_tier == 'pro' ? 2000 : 1000 # en centavos: $20 USD o $10 USD
    plan_name = plan_tier == 'pro' ? 'Gig Manager Pro (En Ajuste por Desarrollador)' : 'Gig Manager Base'

    # Simulación directa en ambiente de desarrollo si aún no se han configurado llaves reales de Stripe
    if ENV['STRIPE_SECRET_KEY'].blank? && !Rails.application.credentials.dig(:stripe, :secret_key).present?
      if Rails.env.development?
        current_company.update!(
          subscription_status: 'active',
          plan_tier: plan_tier,
          stripe_customer_id: "cus_simulated_#{SecureRandom.hex(6)}",
          stripe_subscription_id: "sub_simulated_#{SecureRandom.hex(6)}"
        )
        redirect_to subscriptions_path, notice: "¡Modo Simulación Activo! Tu suscripción al plan #{plan_tier.capitalize} ($#{price_amount / 100}/mes) ha sido activada correctamente."
        return
      end
    end

    session_params = {
      payment_method_types: ['card'],
      mode: 'subscription',
      line_items: [{
        price_data: {
          currency: 'usd',
          product_data: {
            name: plan_name,
            description: "Suscripción mensual a #{plan_name} para #{current_company.name}"
          },
          unit_amount: price_amount,
          recurring: { interval: 'month' }
        },
        quantity: 1
      }],
      metadata: {
        company_id: current_company.id,
        plan_tier: plan_tier
      },
      success_url: "#{subscriptions_url}?session_id={CHECKOUT_SESSION_ID}&success=true",
      cancel_url: "#{subscriptions_url}?canceled=true"
    }

    if current_company.stripe_customer_id.present?
      session_params[:customer] = current_company.stripe_customer_id
    else
      session_params[:customer_email] = current_user.email
    end

    checkout_session = Stripe::Checkout::Session.create(session_params)
    redirect_to checkout_session.url, allow_other_host: true
  rescue => e
    redirect_to subscriptions_path, alert: "Error al iniciar Stripe Checkout: #{e.message}"
  end

  def portal
    unless current_company.stripe_customer_id.present?
      redirect_to subscriptions_path, alert: "Aún no tienes un registro de cliente activo en Stripe."
      return
    end

    if current_company.stripe_customer_id.start_with?("cus_simulated_")
      redirect_to subscriptions_path, notice: "Estás en modo simulación local. Para administrar suscripciones reales en Stripe configura tus llaves de producción."
      return
    end

    portal_session = Stripe::BillingPortal::Session.create(
      customer: current_company.stripe_customer_id,
      return_url: subscriptions_url
    )
    redirect_to portal_session.url, allow_other_host: true
  rescue => e
    redirect_to subscriptions_path, alert: "Error al acceder al Portal de Stripe: #{e.message}"
  end
end
