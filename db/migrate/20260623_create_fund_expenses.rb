class CreateFundExpenses < ActiveRecord::Migration[7.1]
  def change
    create_table :fund_expenses do |t|
      t.references :fund_allocation, null: false, foreign_key: true
      t.decimal :amount, precision: 12, scale: 2, default: 0.0, null: false
      t.string :currency, default: 'USD'
      t.text :notes
      t.datetime :spent_at

      t.timestamps
    end
  end
end
