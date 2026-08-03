class CreateSubCategories < ActiveRecord::Migration[7.1]
  def change
    create_table :sub_categories do |t|
      t.string :name, null: false
      t.string :category, null: false, default: "Cables"

      t.timestamps
    end
    add_index :sub_categories, [:category, :name], unique: true
  end
end
