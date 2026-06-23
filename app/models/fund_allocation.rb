class FundAllocation < ApplicationRecord
  belongs_to :gig

  FUND_TYPES = %w[capital repairs savings transport other].freeze

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :fund_type, presence: true, inclusion: { in: FUND_TYPES }
  validates :currency, presence: true

  def fund_label
    case fund_type
    when 'capital' then 'Capital del Grupo'
    when 'repairs' then 'Fondo de Reparaciones'
    when 'savings' then 'Ahorros'
    when 'transport' then 'Transporte'
    else 'Otro'
    end
  end

  has_many :fund_expenses, dependent: :destroy

  def spent_total
    fund_expenses.sum(:amount).to_f
  end

  def remaining
    amount.to_f - spent_total
  end
end
