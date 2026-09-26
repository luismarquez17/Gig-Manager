require "test_helper"

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
end
