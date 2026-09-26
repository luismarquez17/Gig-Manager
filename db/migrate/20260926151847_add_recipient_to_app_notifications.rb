class AddRecipientToAppNotifications < ActiveRecord::Migration[7.1]
  def change
    add_reference :app_notifications, :recipient, null: true, foreign_key: { to_table: :users }, index: true
  end
end
