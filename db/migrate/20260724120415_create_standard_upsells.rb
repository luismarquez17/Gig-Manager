class CreateStandardUpsells < ActiveRecord::Migration[7.1]
  def change
    create_table :standard_upsells do |t|
      t.string :key
      t.string :title, null: false
      t.string :emoji
      t.decimal :price, precision: 10, scale: 2, default: 0.0
      t.string :currency, default: 'USD'
      t.text :description
      t.boolean :active, default: true, null: false

      t.timestamps
    end
    add_index :standard_upsells, :key, unique: true
  end
end
