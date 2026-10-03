class AddPaymentMethodAndReceiptNumberToGigPayments < ActiveRecord::Migration[7.1]
  def change
    add_column :gig_payments, :payment_method, :string, default: 'cash', null: false
    add_column :gig_payments, :receipt_number, :string

    add_index :gig_payments, :receipt_number
  end
end
