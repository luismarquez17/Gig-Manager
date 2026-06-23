class AddInventoryItemIdToMaintenanceRecords < ActiveRecord::Migration[7.1]
  def change
    add_reference :maintenance_records, :inventory_item, null: true, foreign_key: true
  end
end
