class AddVoucherAndApprovalToGigPayments < ActiveRecord::Migration[7.1]
  def change
    add_column :gig_payments, :status, :string, default: 'approved', null: false
    add_column :gig_payments, :reported_by_client, :boolean, default: false, null: false
    add_column :gig_payments, :reference_number, :string
    add_column :gig_payments, :receipt_image_base64, :text
    add_column :gig_payments, :rejection_reason, :string
    add_column :gig_payments, :approved_at, :datetime
    add_column :gig_payments, :approved_by_id, :bigint

    add_index :gig_payments, :status
    add_index :gig_payments, :reported_by_client
    add_foreign_key :gig_payments, :users, column: :approved_by_id, if_not_exists: true
  end
end
