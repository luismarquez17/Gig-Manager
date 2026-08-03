class StaffAssignment < ApplicationRecord
  belongs_to :user
  belongs_to :gig

  validates :agreed_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  def total_paid
    gig.employee_payments.where(user_id: user_id).sum(:amount).to_f
  end

  def balance
    agreed_amount.to_f - total_paid
  end

  def pending_balance
    [agreed_amount.to_f - total_paid, 0].max
  end

  def worker_owes_company
    diff = total_paid - agreed_amount.to_f
    diff > 0 ? diff : 0.0
  end
end
