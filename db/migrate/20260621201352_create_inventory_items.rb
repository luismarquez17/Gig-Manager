class CreateInventoryItems < ActiveRecord::Migration[7.1]
  class MigrationItem < ActiveRecord::Base
    self.table_name = :items
  end

  class MigrationInventoryItem < ActiveRecord::Base
    self.table_name = :inventory_items
  end

  def up
    create_table :inventory_items do |t|
      t.references :item, null: false, foreign_key: true
      t.string :status, null: false, default: 'available'
      t.string :serial_number
      t.timestamps
    end

    MigrationItem.find_each do |item|
      qty = item.quantity || 0
      next if qty <= 0

      status_mapping = case item.status
                       when 'Dañado' then 'damaged'
                       when 'Excelente', 'Operativo' then 'available'
                       else 'available'
                       end

      qty.times do
        MigrationInventoryItem.create!(
          item_id: item.id,
          status: status_mapping
        )
      end
    end
  end

  def down
    drop_table :inventory_items
  end
end
