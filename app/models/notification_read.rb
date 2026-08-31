class NotificationRead < ApplicationRecord
  belongs_to :user
  belongs_to :app_notification

  validates :user_id, uniqueness: { scope: :app_notification_id }
end
