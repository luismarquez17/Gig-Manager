class CreateSubscriptionPayments < ActiveRecord::Migration[7.1]
  def change
    create_table :subscription_payments do |t|
      t.references :company, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, default: 0.0, null: false
      t.string :currency, default: "USD"
      t.string :payment_method, null: false
      t.string :reference_number, null: false
      t.string :plan_tier, default: "starter", null: false
      t.string :status, default: "pending", null: false
      t.text :notes
      t.datetime :approved_at

      t.timestamps
    end

    add_index :subscription_payments, :status
  end
end
