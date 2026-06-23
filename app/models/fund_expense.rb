class FundExpense < ApplicationRecord
  belongs_to :fund_allocation
  belongs_to :maintenance_record, optional: true

  validates :amount, presence: true, numericality: { greater_than: 0 }

  before_create :set_spent_at

  private

  def set_spent_at
    self.spent_at ||= Time.current
  end
end
