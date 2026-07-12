class EmployeePayment < ApplicationRecord
  belongs_to :user
  belongs_to :gig, optional: true
  has_many :fund_expenses, dependent: :destroy

  validates :amount, presence: true, numericality: { greater_than: 0 }
end
