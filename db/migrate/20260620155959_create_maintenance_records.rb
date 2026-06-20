class CreateMaintenanceRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :maintenance_records do |t|
      t.references :item, null: false, foreign_key: true
      t.references :gig, null: true, foreign_key: true
      t.text :description, null: false
      t.integer :status, default: 0, null: false
      t.decimal :cost, precision: 10, scale: 2, default: 0.00, null: false
      t.date :started_at
      t.date :completed_at

      t.timestamps
    end
  end
end
