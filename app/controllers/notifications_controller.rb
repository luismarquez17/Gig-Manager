class NotificationsController < ApplicationController
  before_action :require_leader!, only: [:create, :destroy]

  def index
    @all_notifications = current_user.app_notifications
    @unread_count = current_user.unread_notifications_count

    @filter = params[:filter].presence || 'all'
    @type_filter = params[:type].presence

    @notifications = case @filter
    when 'unread'
      @all_notifications.unread_by(current_user)
    else
      @all_notifications
    end

    if @type_filter.present?
      @notifications = @notifications.where(notification_type: @type_filter)
    end

    if params[:target_area].present?
      @notifications = @notifications.where(target_area: params[:target_area])
    end

    @upcoming_gigs = current_company.gigs.where('date >= ?', Date.today).order(date: :asc) if current_company.present?
    @upcoming_gigs ||= Gig.none

    @new_notification = AppNotification.new(
      target_area: 'all_areas',
      notification_type: 'general'
    )
  end

  def create
    @notification = AppNotification.new(notification_params)
    @notification.sender = current_user
    @notification.company = current_company

    if @notification.save
      respond_to do |format|
        format.html { redirect_to notifications_path, notice: "¡Notificación transmitida en tiempo real al #{@notification.target_area_label}!" }
        format.turbo_stream
      end
    else
      redirect_to notifications_path, alert: "No se pudo enviar la notificación: #{@notification.errors.full_messages.join(', ')}"
    end
  end

  def mark_as_read
    @notification = current_user.app_notifications.find_by(id: params[:id])
    if @notification
      @notification.mark_as_read_by!(current_user)
    end

    respond_to do |format|
      format.html { redirect_to notifications_path(filter: params[:filter]) }
      format.turbo_stream { render turbo_stream: turbo_stream.replace("notification_#{params[:id]}", partial: "notifications/notification", locals: { notification: @notification }) }
    end
  end

  def mark_all_as_read
    unread_ids = current_user.app_notifications.unread_by(current_user).pluck(:id)
    if unread_ids.any?
      now = Time.current
      records = unread_ids.map do |notif_id|
        {
          app_notification_id: notif_id,
          user_id: current_user.id,
          read_at: now,
          created_at: now,
          updated_at: now
        }
      end
      NotificationRead.insert_all(records)
    end

    redirect_to notifications_path, notice: "Todas las notificaciones se han marcado como leídas."
  end

  def destroy
    @notification = AppNotification.where(company: current_company).find_by(id: params[:id])
    if @notification
      @notification.destroy
      redirect_to notifications_path, notice: "Notificación eliminada."
    else
      redirect_to notifications_path, alert: "Notificación no encontrada."
    end
  end

  private

  def notification_params
    params.require(:app_notification).permit(:title, :message, :target_area, :notification_type, :action_url)
  end
end
