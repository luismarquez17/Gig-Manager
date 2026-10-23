require "test_helper"
require "minitest/mock"

class AppNotificationTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
    @leader = users(:one)
    @staff = users(:two)
    @musician = users(:musician)
  end

  test "personal notification is only visible to the recipient" do
    notification = AppNotification.create!(
      company: @company,
      sender: @leader,
      recipient: @musician,
      target_area: 'musicians',
      notification_type: 'gig_alert',
      title: "🎸 Has sido asignado a un evento",
      message: "Show personal"
    )

    assert_includes @musician.app_notifications, notification
    assert_not_includes @staff.app_notifications, notification
    assert_not_includes @leader.app_notifications, notification
    assert_equal "Personal", notification.target_area_label
  end

  test "area notification without recipient is visible to all members of that area and leaders" do
    area_notification = AppNotification.create!(
      company: @company,
      sender: @leader,
      recipient: nil,
      target_area: 'musicians',
      notification_type: 'general',
      title: "📢 Ensayo general",
      message: "Para todos los músicos"
    )

    assert_includes @musician.app_notifications, area_notification
    assert_not_includes @staff.app_notifications, area_notification
  end

  test "all_areas notification is visible to everyone in the company" do
    broadcast = AppNotification.create!(
      company: @company,
      sender: @leader,
      recipient: nil,
      target_area: 'all_areas',
      notification_type: 'general',
      title: "Anuncio de la empresa",
      message: "Para todos"
    )

    assert_includes @leader.app_notifications, broadcast
    assert_includes @musician.app_notifications, broadcast
    assert_includes @staff.app_notifications, broadcast
  end

  test "upsell notification is categorized as upsell, not financial, with clean labels" do
    upsell_notif = AppNotification.new(
      company: @company,
      target_area: 'leaders',
      notification_type: 'gig_alert',
      title: "🚀 Solicitud de Adicional: Máquina de Humo",
      message: "Alexander Perdomo ha solicitado 💨 Máquina de Humo ($40.00 USD).",
      action_url: "/gigs/1"
    )

    assert_not upsell_notif.payment_related?
    assert_equal 'upsell', upsell_notif.toast_category
    assert_equal '🚀', upsell_notif.type_icon
    assert_equal '✨ Revisar Solicitud ➔', upsell_notif.action_label
  end

  test "voucher payment notification is categorized as financial with payment labels" do
    payment_notif = AppNotification.new(
      company: @company,
      target_area: 'leaders',
      notification_type: 'payment_alert',
      title: "💳 ¡Nuevo Comprobante de Abono de Cliente!",
      message: "El cliente ha enviado un comprobante de abono de $500.00.",
      action_url: "/gigs/1"
    )

    assert payment_notif.payment_related?
    assert_equal 'financial', payment_notif.toast_category
    assert_equal '💰', payment_notif.type_icon
    assert_equal '💳 Gestionar Abono ➔', payment_notif.action_label
  end

  test "broadcast_notification broadcasts to exactly one stream per audience without duplicating" do
    received_streams = []
    Turbo::StreamsChannel.stub :broadcast_append_to, ->(stream, target:, html:) {
      received_streams << stream.last
    } do
      Turbo::StreamsChannel.stub :broadcast_prepend_to, ->(stream, target:, partial:, locals:) {} do
        notif = AppNotification.create!(
          company: @company,
          sender: @leader,
          target_area: 'leaders',
          notification_type: 'gig_alert',
          title: "🚀 Solicitud de Adicional: Máquina de Humo",
          message: "Mensaje test"
        )
      end
    end

    # Must only broadcast to notifications_leaders once, NOT notifications_all_areas as well!
    assert_equal ["notifications_leaders"], received_streams
  end
end
