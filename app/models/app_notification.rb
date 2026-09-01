# frozen_string_literal: true

class AppNotification < ApplicationRecord
  include TenantScoped

  belongs_to :sender, class_name: 'User', optional: true
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

  scope :for_role, ->(role) {
    role_str = role.to_s
    case role_str
    when 'leader', 'superadmin'
      where(target_area: [:all_areas, :leaders])
    when 'musician'
      where(target_area: [:all_areas, :musicians])
    when 'staff'
      where(target_area: [:all_areas, :staffs])
    else
      where(target_area: :all_areas)
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

    channels = if target_area == 'all_areas'
      ["notifications_leaders", "notifications_musicians", "notifications_staffs", "notifications_all_areas"]
    else
      ["notifications_#{target_area}", "notifications_all_areas"]
    end

    channels.uniq.each do |channel_suffix|
      stream_name = [company, channel_suffix]

      # Prepend to list
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
      
      script_html = "<script>if (typeof showToast === 'function') { showToast('#{clean_title}: #{clean_msg}', '#{toast_type}'); } if (typeof updateUnreadBadge === 'function') { updateUnreadBadge(1); }</script>"

      Turbo::StreamsChannel.broadcast_append_to(
        stream_name,
        target: "toast-container",
        html: script_html
      )
    end
  end
end
