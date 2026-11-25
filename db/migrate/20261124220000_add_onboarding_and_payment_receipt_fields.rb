class AddOnboardingAndPaymentReceiptFields < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :onboarding_completed, :boolean, default: true, null: false

    add_column :subscription_payments, :receipt_image_base64, :text
    add_column :subscription_payments, :rejection_reason, :string
    add_column :subscription_payments, :rejected_at, :datetime
    add_column :subscription_payments, :approved_by_id, :bigint
    add_index :subscription_payments, :approved_by_id
  end
end
