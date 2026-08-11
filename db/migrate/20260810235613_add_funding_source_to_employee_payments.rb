class AddFundingSourceToEmployeePayments < ActiveRecord::Migration[7.1]
  def change
    add_column :employee_payments, :funding_source, :string, default: 'payroll_fund', null: false
    add_column :employee_payments, :external_source_name, :string
  end
end
