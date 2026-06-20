class CreateKitsAndKitItems < ActiveRecord::Migration[7.1]
  def change
    create_table :kits do |t|
      t.string :name, null: false
      t.text :description

      t.timestamps
    end

    create_table :kit_items do |t|
      t.belongs_to :kit, null: false, foreign_key: true
      t.belongs_to :item, null: false, foreign_key: true
      t.integer :quantity, default: 1, null: false

      t.timestamps
    end
  end
end
