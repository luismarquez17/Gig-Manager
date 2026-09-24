class CreateCashAdjustments < ActiveRecord::Migration[7.1]
  def change
    create_table :cash_adjustments do |t|
      t.references :company, null: false, foreign_key: true
      t.decimal :amount, precision: 12, scale: 2, default: "0.0", null: false
      t.string :currency, default: "USD", null: false
      t.integer :adjustment_type, default: 0, null: false
      t.date :date, null: false
      t.text :description, null: false
      t.references :user, foreign_key: true

      t.timestamps
    end

    add_index :cash_adjustments, :date
    add_index :cash_adjustments, :adjustment_type
  end
end
