class AddMaintenanceRecordToFundExpenses < ActiveRecord::Migration[7.1]
  def change
    add_reference :fund_expenses, :maintenance_record, foreign_key: true
  end
end
