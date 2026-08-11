class AddApprovalStatusToEmployeePayments < ActiveRecord::Migration[7.1]
  def change
    add_column :employee_payments, :status, :string, default: 'approved', null: false
    add_column :employee_payments, :reported_by_worker, :boolean, default: false, null: false
    add_column :employee_payments, :rejection_reason, :string
    add_column :employee_payments, :approved_at, :datetime
    add_index :employee_payments, :status
  end
end
