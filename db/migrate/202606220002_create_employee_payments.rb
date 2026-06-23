class CreateEmployeePayments < ActiveRecord::Migration[7.0]
  def change
    create_table :employee_payments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :gig, foreign_key: true
      t.decimal :amount, precision: 12, scale: 2, null: false, default: 0.0
      t.string :currency, default: 'USD'
      t.date :date_paid
      t.string :payment_method
      t.text :notes

      t.timestamps
    end
  end
end
