class CreateGigPayments < ActiveRecord::Migration[7.0]
  def change
    create_table :gig_payments do |t|
      t.references :gig, null: false, foreign_key: true
      t.decimal :amount, precision: 12, scale: 2, null: false, default: 0.0
      t.string :currency, default: 'USD'
      t.date :date_paid
      t.boolean :is_advance, default: false
      t.string :payer_name
      t.date :for_date
      t.string :category
      t.text :notes

      t.timestamps
    end
  end
end
