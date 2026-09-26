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

  def type_icon
    icon = case notification_type
    when 'general'       then '📢'
    when 'gig_alert'     then '🎸'
    when 'payment_alert' then '💰'
    when 'urgent'        then '🚨'
    else '🔔'
    end
    icon.dup.force_encoding('UTF-8')
  end

  def type_label
    str = case notification_type
    when 'general'       then 'Recordatorio Operativo'
    when 'gig_alert'     then 'Evento / Show'
    when 'payment_alert' then 'Pago / Finanzas'
    when 'urgent'        then 'Urgente'
    else notification_type.humanize
    end
    str.dup.force_encoding('UTF-8')
  end

  private

  def broadcast_notification
    return unless company_id.present?

    channels = if recipient_id.present?
      ["notifications_user_#{recipient_id}"]
    elsif target_area == 'all_areas'
      ["notifications_leaders", "notifications_musicians", "notifications_staffs", "notifications_all_areas"]
    else
      ["notifications_#{target_area}", "notifications_all_areas"]
    end

    channels.uniq.each do |channel_suffix|
      stream_name = [company, channel_suffix]

      # Prepend to list in notifications center
      Turbo::StreamsChannel.broadcast_prepend_to(
        stream_name,
        target: "notifications_list",
        partial: "notifications/notification",
        locals: { notification: self, current_user: nil }
      )

      # Broadcast toast pop-up and badge bump script
      clean_title = ActionController::Base.helpers.j(title.to_s)
      clean_msg = ActionController::Base.helpers.j(message.to_s.truncate(80))
      toast_type = notification_type == 'urgent' ? 'error' : 'success'
      sound_type = (notification_type == 'urgent' || notification_type == 'error') ? 'urgent' : (notification_type == 'payment_alert' ? 'payment' : 'default')
      url_link = action_url.presence || "/notifications"
      
      script_html = <<~HTML
        <div data-toast="1" style="pointer-events: all; display: flex; align-items: flex-start; gap: 10px; padding: 14px 16px; border-radius: 14px; font-family: Inter, sans-serif; font-size: 0.9rem; font-weight: 600; line-height: 1.4; box-shadow: 0 8px 30px rgba(0,0,0,0.14); border: 1px solid #{toast_type == 'error' ? '#fca5a5' : '#86efac'}; background: #{toast_type == 'error' ? '#fff1f2' : '#f0fdf4'}; color: #{toast_type == 'error' ? '#9f1239' : '#15803d'}; position: relative; overflow: hidden; max-width: 100%;">
          <span style="font-size:1.3em;flex-shrink:0;">#{type_icon}</span>
          <div style="flex:1;">
            <div style="font-weight: 800; font-size: 0.95em; color: #0f172a; margin-bottom: 2px;">#{ERB::Util.html_escape(title)}</div>
            <div style="font-size: 0.85em; color: #334155;">#{ERB::Util.html_escape(message.to_s.truncate(100))}</div>
            <a href="#{url_link}" style="display: inline-block; margin-top: 6px; font-size: 0.82em; font-weight: 700; color: #2563eb; text-decoration: underline;">Ver detalles ➔</a>
          </div>
          <button onclick="this.closest('[data-toast]').remove()" style="background:none;border:none;cursor:pointer;font-size:1.1em;color:inherit;opacity:0.6;padding:0;margin:0;line-height:1;flex-shrink:0;" title="Cerrar">✕</button>
          <div style="position:absolute;bottom:0;left:0;height:3px;background:#{toast_type == 'error' ? '#f87171' : '#22c55e'};width:100%;transform-origin:left;animation:toastProgress 6s linear forwards;border-radius:0 0 14px 14px;"></div>
        </div>
        <script>
          if (typeof playNotificationSound === 'function') { playNotificationSound('#{sound_type}'); }
          if (typeof sendDeviceNotification === 'function') { sendDeviceNotification('#{clean_title}', '#{clean_msg}', { url: '#{url_link}' }); }
          if (typeof updateUnreadBadge === 'function') { updateUnreadBadge(1); }
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
