class CreateShoppingItems < ActiveRecord::Migration[7.1]
  def change
    create_table :shopping_items do |t|
      t.string :name, null: false
      t.string :category
      t.text :reason
      t.text :purpose
      t.decimal :estimated_price, precision: 12, scale: 2
      t.string :currency, default: "USD"
      t.integer :priority, default: 1, null: false   # 0=low, 1=medium, 2=high
      t.integer :status, default: 0, null: false     # 0=pending, 1=purchased
      t.text :notes

      t.timestamps
    end

    add_index :shopping_items, :status
    add_index :shopping_items, :priority
  end
end
