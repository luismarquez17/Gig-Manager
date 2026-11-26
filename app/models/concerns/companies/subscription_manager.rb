# frozen_string_literal: true

module Companies
  module SubscriptionManager
    extend ActiveSupport::Concern

    included do
      DEFAULT_TRIAL_DAYS = 30
      GRACE_PERIOD_DAYS = 3
      REMINDER_DAYS_BEFORE = 2
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
    # ESTADOS DE SUSCRIPCIÓN, GRACIA & FREE TRIAL
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

    def in_grace_period?
      return false if suspended?
      return false unless trial_ends_at.present?

      trial_ends_at <= Time.current && Time.current <= (trial_ends_at + GRACE_PERIOD_DAYS.days)
    end

    def grace_period_expired?
      return true if suspended?
      return false unless trial_ends_at.present?

      Time.current > (trial_ends_at + GRACE_PERIOD_DAYS.days)
    end

    def grace_days_left
      return 0 unless in_grace_period?

      deadline = trial_ends_at + GRACE_PERIOD_DAYS.days
      [((deadline - Time.current) / 1.day).ceil, 1].max
    end

    def access_granted?
      return false if suspended?
      return true if in_grace_period?
      return true if trial_active? || subscription_paid_and_active?
      false
    end

    def should_send_upcoming_reminder?
      return false if suspended? || in_grace_period? || grace_period_expired?
      return false unless trial_ends_at.present?

      left = days_left_in_subscription
      left.positive? && left <= REMINDER_DAYS_BEFORE && !upcoming_reminder_sent?
    end

    def upcoming_reminder_sent?
      return false unless trial_ends_at.present?

      cycle_start = trial_ends_at - DEFAULT_TRIAL_DAYS.days
      window_start = [cycle_start, 4.days.ago].max

      AppNotification.where(company_id: id)
                     .where("action_url = ? AND created_at >= ?", "/subscriptions", window_start)
                     .where("title LIKE ?", "%Recordatorio de tu suscripción%")
                     .exists?
    end

    def grace_notification_sent?
      return false unless trial_ends_at.present?

      AppNotification.where(company_id: id)
                     .where("action_url = ? AND created_at >= ?", "/subscriptions", trial_ends_at)
                     .where("title LIKE ?", "%Período de Gracia%")
                     .exists?
    end

    def check_subscription_lifecycle!
      # 1. Enviar recordatorio cariñoso cuando falten 2 días o menos para cumplir los 30 días
      send_upcoming_expiration_reminder! if should_send_upcoming_reminder?

      # 2. Notificar inicio de los 3 días de gracia si el ciclo de 30 días acaba de vencer
      send_grace_period_notification! if in_grace_period? && !grace_notification_sent?

      # 3. Suspender el servicio si se agotaron los 3 días de gracia y no ha pagado
      suspend_for_non_payment! if grace_period_expired? && !suspended?
    end

    def send_upcoming_expiration_reminder!
      days_left = days_left_in_subscription
      days_str = days_left == 1 ? "1 día" : "#{days_left} días"
      exp_date = (I18n.l(trial_ends_at.to_date, format: :long) rescue trial_ends_at.strftime('%d/%m/%Y'))

      msg = "¡Hola! Te recordamos con mucho cariño que a tu ciclo de 30 días en Gig Manager le quedan #{days_str} (finaliza el #{exp_date}). Puedes renovar tu plan con total tranquilidad para que tu equipo continúe sin interrupciones. Recuerda que todos los datos, eventos y balances de tu empresa están y seguirán estando 100% seguros y respaldados con nosotros. ✨"

      notif = AppNotification.create!(
        company_id: id,
        target_area: :leaders,
        notification_type: :general,
        title: "💌 Recordatorio de tu suscripción Gig Manager",
        message: msg,
        action_url: "/subscriptions"
      )
      notif.broadcast_notification rescue nil

      leaders.each do |leader|
        UserMailer.trial_expiring_reminder(leader).deliver_later rescue nil
      end
    end

    def send_grace_period_notification!
      grace_deadline = (I18n.l((trial_ends_at + GRACE_PERIOD_DAYS.days).to_date, format: :long) rescue (trial_ends_at + GRACE_PERIOD_DAYS.days).strftime('%d/%m/%Y'))

      msg = "Tu ciclo de 30 días ha concluido, pero no te preocupes: cuentas con 3 días de gracia (hasta el #{grace_deadline}) para registrar tu pago con calma antes de suspender el servicio. Queremos darte la total tranquilidad de que todos tus datos, eventos y personal están completamente a salvo y seguirán aquí tal como los dejaste."

      notif = AppNotification.create!(
        company_id: id,
        target_area: :leaders,
        notification_type: :urgent,
        title: "⏳ Período de Gracia: 3 días para renovar tu suscripción",
        message: msg,
        action_url: "/subscriptions"
      )
      notif.broadcast_notification rescue nil
    end

    def suspend_for_non_payment!
      update_columns(status: Company.statuses[:suspended], subscription_status: 'suspended')

      msg = "El período de gracia de 3 días ha vencido y el acceso al servicio ha sido temporalmente suspendido por pago pendiente. ¡Ojo! Todos tus datos siguen 100% seguros e intactos en la plataforma. En cuanto reactives tu suscripción con tu pago, encontrarás todo exactamente donde lo dejaste."

      notif = AppNotification.create!(
        company_id: id,
        target_area: :leaders,
        notification_type: :urgent,
        title: "🚫 Servicio suspendido temporalmente por pago pendiente",
        message: msg,
        action_url: "/subscriptions"
      )
      notif.broadcast_notification rescue nil
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
        "Suspendida (Datos Protegidos)"
      elsif in_grace_period?
        "Período de Gracia (#{grace_days_left} #{grace_days_left == 1 ? 'día' : 'días'} restantes)"
      elsif subscription_paid_and_active?
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
