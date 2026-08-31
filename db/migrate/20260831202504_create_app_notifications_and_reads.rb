class CreateAppNotificationsAndReads < ActiveRecord::Migration[7.1]
  def change
    create_table :app_notifications do |t|
      t.references :company, foreign_key: true, index: true
      t.references :sender, foreign_key: { to_table: :users }, null: true, index: true
      t.string :target_area, null: false, default: 'all_areas'
      t.string :title, null: false
      t.text :message, null: false
      t.string :notification_type, null: false, default: 'general'
      t.string :action_url

      t.timestamps
    end
    add_index :app_notifications, :target_area
    add_index :app_notifications, :notification_type

    create_table :notification_reads do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.references :app_notification, null: false, foreign_key: true, index: true
      t.datetime :read_at, null: false

      t.timestamps
    end

    add_index :notification_reads, [:user_id, :app_notification_id], unique: true
  end
end
