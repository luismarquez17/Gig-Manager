# frozen_string_literal: true

module Companies
  module SubscriptionManager
    extend ActiveSupport::Concern

    included do
      DEFAULT_TRIAL_DAYS = 30
      VALID_PLAN_TIERS = ['banda', 'productora', 'salon', 'negocio', 'personalizado', 'full'].freeze

      before_create :set_default_trial_period
    end

    def set_default_trial_period
      self.trial_started_at ||= Time.current
      self.trial_ends_at ||= DEFAULT_TRIAL_DAYS.days.from_now
      self.subscription_status ||= "trialing"
      self.plan_tier ||= "banda"
      self.enabled_modules ||= AppModule.default_hash
    end

    def effective_plan_tier
      check_scheduled_plan_transition! if persisted?
      VALID_PLAN_TIERS.include?(plan_tier.to_s) ? plan_tier.to_s : 'banda'
    end

    def pricing_breakdown(simulated_tier = nil, simulated_modules = nil)
      target_tier = simulated_tier.presence || effective_plan_tier
      target_modules = simulated_modules.presence || enabled_module_keys
      AppModule.calculate_pricing(target_tier, target_modules)
    end

    def calculated_monthly_fee
      pricing_breakdown[:total_price]
    end

    def extra_modules
      pricing_breakdown[:extra_modules_details]
    end

    def has_extra_modules?
      pricing_breakdown[:extra_keys].any?
    end

    # ==========================================
    # CAMBIOS DE PLAN PROGRAMADOS (PRÓXIMO MES)
    # ==========================================

    def has_scheduled_plan_change?
      scheduled_plan_tier.present? && scheduled_change_at.present?
    end

    def effective_scheduled_plan_tier
      VALID_PLAN_TIERS.include?(scheduled_plan_tier.to_s) ? scheduled_plan_tier.to_s : 'banda'
    end

    def scheduled_module_keys
      return [] unless has_scheduled_plan_change?
      if scheduled_modules.is_a?(Hash)
        scheduled_modules.select { |_, v| v == true || v == "1" || v == 1 || v == "true" }.keys.map(&:to_s)
      elsif scheduled_plan_tier.present?
        AppModule.modules_for_package(scheduled_plan_tier)
      else
        []
      end
    end

    def scheduled_pricing_breakdown
      return nil unless has_scheduled_plan_change?
      AppModule.calculate_pricing(effective_scheduled_plan_tier, scheduled_module_keys)
    end

    def scheduled_monthly_fee
      scheduled_pricing_breakdown&.dig(:total_price) || 0.0
    end

    def scheduled_plan_name
      return nil unless has_scheduled_plan_change?
      if effective_scheduled_plan_tier == 'personalizado'
        count = scheduled_module_keys.count
        "Plan Personalizado (#{count} #{count == 1 ? 'Módulo' : 'Módulos'})"
      else
        AppModule.package_info(effective_scheduled_plan_tier)&.dig(:name) || 'Plan Programado'
      end
    end

    def schedule_plan_change!(new_tier, new_modules_hash = {}, effective_date = nil)
      clean_tier = VALID_PLAN_TIERS.include?(new_tier.to_s) ? new_tier.to_s : 'banda'
      effective_date ||= trial_ends_at.presence || 30.days.from_now

      formatted = {}
      if clean_tier == 'personalizado' || new_modules_hash.present?
        AppModule.keys.each do |key|
          val = new_modules_hash[key] || new_modules_hash[key.to_sym]
          formatted[key] = (val == true || val == "1" || val == "true" || val == 1)
        end
      else
        pkg_mods = AppModule.modules_for_package(clean_tier)
        AppModule.keys.each do |key|
          formatted[key] = pkg_mods.include?(key)
        end
      end

      update!(
        scheduled_plan_tier: clean_tier,
        scheduled_modules: formatted,
        scheduled_change_at: effective_date
      )
    end

    def cancel_scheduled_plan_change!
      update!(
        scheduled_plan_tier: nil,
        scheduled_modules: nil,
        scheduled_change_at: nil
      )
    end

    def apply_scheduled_plan_change!
      return unless has_scheduled_plan_change?

      target_tier = effective_scheduled_plan_tier
      target_modules = if scheduled_modules.present?
                         scheduled_modules
                       else
                         AppModule.build_modules_hash(AppModule.modules_for_package(target_tier))
                       end

      update!(
        plan_tier: target_tier,
        enabled_modules: target_modules,
        scheduled_plan_tier: nil,
        scheduled_modules: nil,
        scheduled_change_at: nil
      )
    end

    def check_scheduled_plan_transition!
      if has_scheduled_plan_change? && scheduled_change_at.present? && scheduled_change_at <= Time.current
        apply_scheduled_plan_change!
      end
    end

    # ==========================================
    # ESTADOS DE SUSCRIPCIÓN & FREE TRIAL
    # ==========================================

    def in_trial?
      subscription_status == "trialing"
    end

    def trial_active?
      in_trial? && trial_ends_at.present? && trial_ends_at > Time.current
    end

    def trial_expired?
      in_trial? && trial_ends_at.present? && trial_ends_at <= Time.current
    end

    def days_left_in_trial
      return 0 unless trial_ends_at.present? && trial_ends_at > Time.current
      ((trial_ends_at - Time.current) / 1.day).ceil
    end

    def active_subscription?
      subscription_status == "active"
    end

    def subscription_paid_and_active?
      active_subscription? && trial_ends_at.present? && trial_ends_at > Time.current
    end

    def days_left_in_subscription
      return 0 unless trial_ends_at.present? && trial_ends_at > Time.current
      ((trial_ends_at - Time.current) / 1.day).ceil
    end

    def subscription_expiration_date
      trial_ends_at
    end

    def access_granted?
      return false if suspended?
      return true if active_subscription? || trial_active?
      false
    end

    def plan_tier_name
      if effective_plan_tier == 'personalizado'
        "Plan Personalizado (#{enabled_module_keys.count} #{enabled_module_keys.count == 1 ? 'Módulo' : 'Módulos'})"
      else
        AppModule.package_info(effective_plan_tier)&.dig(:name) || 'Paquete Bandas & Orquestas'
      end
    end

    def subscription_label
      if suspended?
        "Suspendida"
      elsif active_subscription?
        "Suscripción Activa (#{plan_tier_name})"
      elsif trial_active?
        "Prueba Gratuita (#{days_left_in_trial} días restantes)"
      elsif trial_expired?
        "Prueba Gratuita Vencida"
      elsif past_due?
        "Pago Vencido"
      else
        subscription_status.to_s.titleize
      end
    end
  end
end
