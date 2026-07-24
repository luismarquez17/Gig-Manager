class StaffAssignment < ApplicationRecord
  belongs_to :user
  belongs_to :gig

  validates :agreed_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  after_save :sync_employee_payment_expected_amount

  def total_paid
    gig.employee_payments.where(user_id: user_id).sum(:amount).to_f
  end

  def pending_balance
    agreed_amount.to_f - total_paid
  end

  private

  def sync_employee_payment_expected_amount
    payments = gig.employee_payments.where(user_id: user_id)
    if payments.any?
      payments.update_all(expected_amount: agreed_amount.to_f)
    end
  end
end
