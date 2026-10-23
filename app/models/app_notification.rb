# frozen_string_literal: true

class AppNotification < ApplicationRecord
  include TenantScoped

  belongs_to :sender, class_name: 'User', optional: true
  belongs_to :recipient, class_name: 'User', optional: true
  has_many :notification_reads, dependent: :destroy

  enum target_area: {
    all_areas: 'all_areas',
    leaders: 'leaders',
    musicians: 'musicians',
    staffs: 'staffs'
  }

  enum notification_type: {
    general: 'general',
    gig_alert: 'gig_alert',
    payment_alert: 'payment_alert',
    urgent: 'urgent'
  }

  validates :title, :message, :target_area, presence: true

  scope :recent_first, -> { order(created_at: :desc) }

  scope :for_user, ->(user) {
    return none unless user.present?

    role_str = user.role.to_s
    role_areas = case role_str
                 when 'leader', 'superadmin' then [:all_areas, :leaders]
                 when 'musician'             then [:all_areas, :musicians]
                 when 'staff'                then [:all_areas, :staffs]
                 else [:all_areas]
                 end

    where(
      "(app_notifications.recipient_id IS NULL AND app_notifications.target_area IN (:areas)) OR app_notifications.recipient_id = :user_id",
      areas: role_areas,
      user_id: user.id
    )
  }

  scope :for_role, ->(role) {
    role_str = role.to_s
    case role_str
    when 'leader', 'superadmin'
      where(recipient_id: nil, target_area: [:all_areas, :leaders])
    when 'musician'
      where(recipient_id: nil, target_area: [:all_areas, :musicians])
    when 'staff'
      where(recipient_id: nil, target_area: [:all_areas, :staffs])
    else
      where(recipient_id: nil, target_area: :all_areas)
    end
  }

  scope :unread_by, ->(user) {
    return none unless user.present?
    where.not(id: NotificationRead.where(user_id: user.id).select(:app_notification_id))
  }

  scope :read_by, ->(user) {
    return none unless user.present?
    where(id: NotificationRead.where(user_id: user.id).select(:app_notification_id))
  }

  after_create_commit :broadcast_notification

  def read_by?(user)
    return false unless user.present?
    notification_reads.exists?(user_id: user.id)
  end

  def mark_as_read_by!(user)
    return unless user.present?
    notification_reads.find_or_create_by!(user: user) do |read|
      read.read_at = Time.current
    end
  end

  def target_area_label
    return "Personal" if recipient_id.present?

    str = case target_area
    when 'all_areas' then 'Todas las áreas'
    when 'leaders'   then 'Área de Líderes'
    when 'musicians' then 'Área de Músicos'
    when 'staffs'    then 'Área de Staffs'
    else target_area.humanize
    end
    str.dup.force_encoding('UTF-8')
  end

  def payment_related?
    payment_alert? ||
      title.to_s.match?(/abono|comprobante|voucher|recibo oficial/i) ||
      (message.to_s.match?(/comprobante de abono|comprobante de pago|voucher/i) && !title.to_s.match?(/adicional|upsell/i))
  end

  def toast_category
    t = title.to_s.downcase
    if notification_type == 'urgent'
      'urgent'
    elsif payment_related?
      'financial'
    elsif t.include?('adicional') || t.include?('upsell')
      'upsell'
    elsif t.include?('contrato')
      'contract'
    else
      'general'
    end
  end

  def action_label
    t = title.to_s.downcase
    m = message.to_s.downcase

    if t.include?('comprobante') || t.include?('abono') || (payment_alert? && m.include?('abono'))
      '💳 Gestionar Abono ➔'
    elsif t.include?('adicional') || t.include?('upsell')
      '✨ Revisar Solicitud ➔'
    elsif t.include?('contrato')
      '📄 Ver Contrato ➔'
    elsif t.include?('asignad')
      recipient_id.present? ? '🎵 Ver Mi Show ➔' : '👥 Ver Personal ➔'
    elsif t.include?('reporte de pago') || (payment_alert? && m.include?('recibido'))
      '📋 Confirmar Pago ➔'
    elsif payment_alert?
      '💵 Ver Cuentas ➔'
    elsif action_url.to_s.include?('/gigs')
      '🎵 Ver Evento ➔'
    else
      'Ver detalles ➔'
    end
  end

  def toast_badge_html
    case toast_category
    when 'financial'
      "<div class='app-toast-badge badge-financial'><span class='app-toast-dot'></span>💰 ABONO REPORTADO</div>"
    when 'upsell'
      "<div class='app-toast-badge badge-upsell'><span class='app-toast-dot'></span>✨ SOLICITUD DE ADICIONAL</div>"
    when 'contract'
      "<div class='app-toast-badge badge-contract'><span class='app-toast-dot'></span>✍️ CONTRATO FIRMADO</div>"
    when 'urgent'
      "<div class='app-toast-badge badge-urgent'><span class='app-toast-dot'></span>🚨 PRIORIDAD ALTA</div>"
    else
      ""
    end
  end

  def type_icon
    t = title.to_s.downcase
    icon = if t.include?('adicional') || t.include?('upsell')
             '🚀'
           elsif t.include?('contrato')
             '✍️'
           elsif notification_type == 'urgent'
             '🚨'
           elsif notification_type == 'payment_alert' || payment_related?
             '💰'
           elsif notification_type == 'gig_alert'
             '🎸'
           elsif notification_type == 'general'
             '📢'
           else
             '🔔'
           end
    icon.dup.force_encoding('UTF-8')
  end

  def type_label
    str = case notification_type
    when 'general'       then 'Recordatorio Operativo'
    when 'gig_alert'     then 'Evento / Show'
    when 'payment_alert' then 'Abono / Finanzas VIP'
    when 'urgent'        then 'Urgente'
    else payment_related? ? 'Abono / Finanzas VIP' : notification_type.humanize
    end
    str.dup.force_encoding('UTF-8')
  end

  private

  def broadcast_notification
    return unless company_id.present?

    channels = if recipient_id.present?
      ["notifications_user_#{recipient_id}"]
    elsif target_area == 'all_areas'
      ["notifications_all_areas"]
    elsif target_area.present?
      ["notifications_#{target_area}"]
    else
      ["notifications_all_areas"]
    end

    category = toast_category
    sound_type = case category
                 when 'urgent' then 'urgent'
                 when 'financial' then 'payment'
                 else 'default'
                 end

    clean_title = ActionController::Base.helpers.j(title.to_s)
    clean_msg = ActionController::Base.helpers.j(message.to_s.truncate(95))
    url_link = action_url.presence || "/notifications"

    channels.uniq.each do |channel_suffix|
      stream_name = [company, channel_suffix]

      # Prepend to list in notifications center
      Turbo::StreamsChannel.broadcast_prepend_to(
        stream_name,
        target: "notifications_list",
        partial: "notifications/notification",
        locals: { notification: self, current_user: nil }
      )

      # Broadcast clean, theme-safe toast pop-up and badge bump script
      script_html = <<~HTML
        <div id="toast-notif-#{id}" data-toast="1" data-notif-id="#{id}" class="app-toast toast-#{category}">
          <span class="app-toast-icon">#{type_icon}</span>
          <div class="app-toast-body">
            #{toast_badge_html}
            <div class="app-toast-title">#{ERB::Util.html_escape(title)}</div>
            <div class="app-toast-message">#{ERB::Util.html_escape(message.to_s.truncate(110))}</div>
            <a href="#{url_link}" class="app-toast-link">#{action_label}</a>
          </div>
          <button type="button" class="app-toast-close" onclick="dismissAppToast(this.closest('[data-toast]'))" title="Cerrar">✕</button>
          <div class="app-toast-bar"></div>
        </div>
        <script>
          if (typeof playNotificationSound === 'function') { playNotificationSound('#{sound_type}'); }
          if (typeof sendDeviceNotification === 'function') { sendDeviceNotification('#{clean_title}', '#{clean_msg}', { url: '#{url_link}' }); }
          if (typeof updateUnreadBadge === 'function') { updateUnreadBadge(1); }
          var el = document.getElementById('toast-notif-#{id}');
          if (el && typeof initAppToast === 'function') { initAppToast(el); }
        </script>
      HTML

      Turbo::StreamsChannel.broadcast_append_to(
        stream_name,
        target: "toast-container",
        html: script_html
      )
    end
  rescue Exception => e
    Rails.logger.error("Error en AppNotification#broadcast_notification: #{e.message}")
  end
end
