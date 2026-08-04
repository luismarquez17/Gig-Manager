class EmployeePayment < ApplicationRecord
  include TenantScoped

  belongs_to :user
  belongs_to :gig, optional: true
  has_many :fund_expenses, dependent: :destroy

  before_validation :ensure_expected_amount

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :expected_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }

  private

  def ensure_expected_amount
    self.expected_amount = 0.0 if expected_amount.nil? || expected_amount.to_s.blank?
  end
end
