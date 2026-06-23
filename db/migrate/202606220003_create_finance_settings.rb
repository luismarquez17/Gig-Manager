class CreateFinanceSettings < ActiveRecord::Migration[7.0]
  def change
    create_table :finance_settings do |t|
      t.decimal :reinvest_rate, precision: 5, scale: 2, default: 0.0, null: false
      t.timestamps
    end
  end
end
