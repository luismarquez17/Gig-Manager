class AddEmployeePaymentToFundExpenses < ActiveRecord::Migration[7.1]
  def change
    add_reference :fund_expenses, :employee_payment, null: true, foreign_key: true
  end
end
