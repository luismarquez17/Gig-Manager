class AddAgreedAmountToStaffAssignments < ActiveRecord::Migration[7.1]
  def change
    add_column :staff_assignments, :agreed_amount, :decimal, precision: 12, scale: 2, default: 0.0, null: false
  end
end
