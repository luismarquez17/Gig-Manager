class CreatePresetBudgets < ActiveRecord::Migration[7.1]
  def change
    create_table :preset_budgets do |t|
      t.string :title
      t.text :description
      t.decimal :price, precision: 10, scale: 2
      t.string :currency, default: "USD"

      t.timestamps
    end
  end
end
