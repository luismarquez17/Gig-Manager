class CreateInvestments < ActiveRecord::Migration[7.1]
  def change
    create_table :investments do |t|
      t.string :description
      t.string :category
      t.decimal :amount
      t.string :currency
      t.date :date
      t.text :notes
      t.string :receipt_number

      t.timestamps
    end
  end
end
