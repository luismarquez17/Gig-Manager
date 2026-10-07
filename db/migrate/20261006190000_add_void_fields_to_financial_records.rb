class AddVoidFieldsToFinancialRecords < ActiveRecord::Migration[7.1]
  def change
    # Gig Payments
    add_column :gig_payments, :voided_at, :datetime
    add_column :gig_payments, :void_reason, :string
    add_column :gig_payments, :voided_by_id, :bigint
    add_foreign_key :gig_payments, :users, column: :voided_by_id, if_not_exists: true

    # Employee Payments
    add_column :employee_payments, :voided_at, :datetime
    add_column :employee_payments, :void_reason, :string
    add_column :employee_payments, :voided_by_id, :bigint
    add_column :employee_payments, :receipt_number, :string
    add_foreign_key :employee_payments, :users, column: :voided_by_id, if_not_exists: true
    add_index :employee_payments, :receipt_number, if_not_exists: true

    # Cash Adjustments
    add_column :cash_adjustments, :status, :string, default: 'approved', null: false
    add_column :cash_adjustments, :voided_at, :datetime
    add_column :cash_adjustments, :void_reason, :string
    add_column :cash_adjustments, :voided_by_id, :bigint
    add_foreign_key :cash_adjustments, :users, column: :voided_by_id, if_not_exists: true
    add_index :cash_adjustments, :status, if_not_exists: true
  end
end
