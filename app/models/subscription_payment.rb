class SubscriptionPayment < ApplicationRecord
  belongs_to :company
  belongs_to :user
  belongs_to :approved_by, class_name: 'User', optional: true

  has_one_attached :receipt_image

  scope :pending, -> { where(status: 'pending') }
  scope :approved, -> { where(status: 'approved') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :without_receipt_image, -> { select(column_names - ["receipt_image_base64"]) }

  validates :payment_method, :reference_number, :amount, presence: true

  before_save :sync_receipt_image_to_base64
  after_commit :ensure_receipt_base64_persisted, on: [:create, :update]
  after_create_commit :broadcast_to_superadmin, if: :pending?

  PAYMENT_METHODS = {
    "zelle" => "🇺🇸 Zelle (USD)",
    "binance" => "🔶 Binance Pay (USDT)",
    "pago_movil" => "🇻🇪 Pago Móvil (Tasa BCV)",
    "transferencia" => "🏦 Transferencia Bancaria (VES / USD)"
  }.freeze

  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end

  def payment_method_label
    PAYMENT_METHODS[payment_method] || payment_method.to_s.titleize.presence || "Manual"
  end

  def voucher_attached?
    receipt_image_base64.present? || (receipt_image.attached? && blob_exists?(receipt_image))
  end

  def voucher_url_or_data
    if receipt_image_base64.present?
      receipt_image_base64
    elsif receipt_image.attached? && blob_exists?(receipt_image)
      receipt_image
    else
      nil
    end
  end

  def approve!(admin_user = nil)
    ActiveRecord::Base.transaction do
      update!(
        status: 'approved',
        approved_at: Time.current,
        approved_by: admin_user,
        rejected_at: nil,
        rejection_reason: nil
      )

      base_date = if company&.trial_ends_at.present? && company.trial_ends_at > Time.current
                    company.trial_ends_at
                  else
                    Time.current
                  end

      updates = {
        status: :active,
        subscription_status: 'active',
        plan_tier: plan_tier,
        trial_ends_at: base_date + 30.days
      }

      if company&.has_scheduled_plan_change?
        updates[:plan_tier] = company.scheduled_plan_tier
        if company.scheduled_modules.present?
          updates[:enabled_modules] = company.scheduled_modules
        else
          package_modules = AppModule.modules_for_package(company.scheduled_plan_tier)
          updates[:enabled_modules] = AppModule.build_modules_hash(package_modules) if package_modules.present?
        end
        updates[:scheduled_plan_tier] = nil
        updates[:scheduled_modules] = nil
        updates[:scheduled_change_at] = nil
      else
        package_modules = AppModule.modules_for_package(plan_tier)
        if package_modules.present?
          updates[:enabled_modules] = AppModule.build_modules_hash(package_modules)
        end
      end

      if company.present?
        effective_mods = updates[:enabled_modules] || company.enabled_module_keys
        updates[:monthly_fee] = AppModule.calculate_pricing(updates[:plan_tier], effective_mods)[:total_price]
        company.update!(updates)
      end
    end

    notify_company_leader!(
      title: "✅ ¡Pago de Suscripción Aprobado!",
      message: "Tu pago ##{reference_number} ($#{'%.2f' % amount.to_f} USD) fue verificado. Tu plan ya está activo por 30 días.",
      notification_type: 'payment_alert'
    )
    broadcast_superadmin_badge_update
  end

  def reject!(reason = nil, _admin_user = nil)
    clean_reason = reason.presence || "No fue posible verificar el comprobante o número de referencia."
    update!(
      status: 'rejected',
      rejection_reason: clean_reason,
      rejected_at: Time.current,
      notes: clean_reason
    )

    notify_company_leader!(
      title: "❌ Reporte de Pago No Verificado",
      message: "El pago ##{reference_number} fue rechazado: #{clean_reason}. Puedes volver a reportarlo con tu captura en Suscripciones.",
      notification_type: 'urgent'
    )
    broadcast_superadmin_badge_update
  end

  def whatsapp_confirmation_url
    formatted_num = user&.formatted_phone_for_whatsapp.presence ||
                    company&.whatsapp_number.to_s.gsub(/\D/, '').presence ||
                    company&.contact_phone.to_s.gsub(/\D/, '').presence
    return nil if formatted_num.blank?

    if formatted_num.start_with?('0') && formatted_num.length == 11
      formatted_num = "58#{formatted_num[1..]}"
    elsif formatted_num.length == 10 && formatted_num.start_with?('4')
      formatted_num = "58#{formatted_num}"
    end

    user_name = user&.display_name.presence || company&.name.presence || "Cliente"
    plan_name_str = (plan_tier.to_s == 'personalizado') ? "Plan Personalizado" : "Plan #{plan_tier.to_s.capitalize}"
    text = "Hola *#{user_name}*! 👋 Tu pago de *$#{'%.2f' % amount.to_f} USD* vía #{payment_method_label} (Ref: #{reference_number}) ha sido verificado exitosamente y tu suscripción a Gig Manager (#{plan_name_str}) está *ACTIVA*."
    "https://wa.me/#{formatted_num}?text=#{ERB::Util.url_encode(text)}"
  rescue => e
    Rails.logger.error "[SubscriptionPayment#whatsapp_confirmation_url] #{e.message}"
    nil
  end

  private

  def sync_receipt_image_to_base64
    encoded = Base64ImageEncoder.encode_from_attachment(attachment_changes['receipt_image'], nil, max_dimension: 1200, quality: 78)
    self.receipt_image_base64 = encoded if encoded.present?
  end

  def ensure_receipt_base64_persisted
    return if receipt_image_base64.present? || !receipt_image.attached? || receipt_image.blob.nil?

    encoded = Base64ImageEncoder.encode_from_attachment(nil, receipt_image, max_dimension: 1200, quality: 78)
    update_column(:receipt_image_base64, encoded) if encoded.present?
  rescue StandardError => e
    Rails.logger.warn("[SubscriptionPayment#ensure_receipt_base64_persisted] #{e.message}")
  end

  def blob_exists?(attachment)
    return false unless attachment&.attached? && attachment.blob
    attachment.blob.service.exist?(attachment.blob.key)
  rescue StandardError
    false
  end

  def notify_company_leader!(title:, message:, notification_type:)
    return unless company.present?

    AppNotification.create!(
      company: company,
      recipient: user,
      target_area: 'leaders',
      notification_type: notification_type,
      title: title,
      message: message,
      action_url: "/subscriptions"
    )
  rescue StandardError => e
    Rails.logger.warn("[SubscriptionPayment#notify_company_leader!] #{e.message}")
  end

  def broadcast_superadmin_badge_update
    pending_count = SubscriptionPayment.pending.count
    badge_html = ApplicationController.render(
      partial: "superadmin/subscription_payments/sidebar_badge",
      locals: { count: pending_count }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      "superadmin_notifications",
      target: "superadmin-pending-payments-badge",
      html: badge_html
    )
    Turbo::StreamsChannel.broadcast_update_to(
      "superadmin_notifications",
      target: "superadmin-pending-count-text",
      html: pending_count.to_s
    )
  rescue StandardError => e
    Rails.logger.warn("[SubscriptionPayment#broadcast_superadmin_badge_update] #{e.message}")
  end

  def broadcast_to_superadmin
    pending_count = SubscriptionPayment.pending.count
    broadcast_superadmin_badge_update

    card_html = ApplicationController.render(
      partial: "superadmin/subscription_payments/pending_payment_card",
      locals: { payment: self }
    )

    Turbo::StreamsChannel.broadcast_remove_to(
      "superadmin_notifications",
      target: "superadmin-no-pending-payments"
    )

    Turbo::StreamsChannel.broadcast_prepend_to(
      "superadmin_notifications",
      target: "superadmin-pending-payments-list",
      html: card_html
    )

    company_name = ERB::Util.html_escape(company&.name || "Nueva Empresa")
    method_label = ERB::Util.html_escape(payment_method_label)
    ref_label = ERB::Util.html_escape(reference_number)
    amt_str = sprintf("%.2f", amount.to_f)
    clean_title = ActionController::Base.helpers.j("💳 Nuevo Pago SaaS: #{company&.name || 'Empresa'}")
    clean_msg = ActionController::Base.helpers.j("$#{amt_str} USD vía #{payment_method_label} (Ref: #{reference_number})")

    toast_html = <<~HTML
      <div id="toast-subpay-#{id}" data-toast="1" data-notif-id="subpay-#{id}" class="app-toast toast-financial">
        <span class="app-toast-icon">💳</span>
        <div class="app-toast-body">
          <div class="app-toast-badge badge-financial"><span class="app-toast-dot"></span>💰 PAGO SAAS REPORTADO</div>
          <div class="app-toast-title">#{company_name} reportó $#{amt_str} USD</div>
          <div class="app-toast-message">#{method_label} • Ref: ##{ref_label}#{voucher_attached? ? ' • 📸 Con captura' : ''}</div>
          <a href="/superadmin/subscription_payments" class="app-toast-link">🔍 Ver Comprobante y Aprobar ➔</a>
        </div>
        <button type="button" class="app-toast-close" onclick="dismissAppToast(this.closest('[data-toast]'))" title="Cerrar">✕</button>
        <div class="app-toast-bar"></div>
      </div>
      <script>
        if (typeof playNotificationSound === 'function') { playNotificationSound('payment'); }
        if (typeof sendDeviceNotification === 'function') { sendDeviceNotification('#{clean_title}', '#{clean_msg}', { url: '/superadmin/subscription_payments' }); }
        if (typeof syncSuperadminCardCsrf === 'function') { syncSuperadminCardCsrf('superadmin-pending-payment-#{id}'); }
        var el = document.getElementById('toast-subpay-#{id}');
        if (el && typeof initAppToast === 'function') { initAppToast(el); }
      </script>
    HTML

    Turbo::StreamsChannel.broadcast_append_to(
      "superadmin_notifications",
      target: "toast-container",
      html: toast_html
    )
  rescue StandardError => e
    Rails.logger.warn("[SubscriptionPayment#broadcast_to_superadmin] #{e.message}")
  end
end
