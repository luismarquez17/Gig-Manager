class CreateFundAllocations < ActiveRecord::Migration[7.1]
  def change
    create_table :fund_allocations do |t|
      t.references :gig, null: false, foreign_key: true
      t.decimal :amount, precision: 12, scale: 2, default: "0.0", null: false
      t.string :currency, default: "USD"
      t.string :fund_type
      t.text :notes

      t.timestamps
    end
  end
end
