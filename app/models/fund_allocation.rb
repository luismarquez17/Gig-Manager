class FundAllocation < ApplicationRecord
  belongs_to :gig

  FUND_TYPES = %w[capital repairs savings transport payroll other].freeze
  FUND_TYPE_LABELS = {
    capital: 'Capital del Grupo',
    repairs: 'Fondo de Reparaciones',
    savings: 'Ahorros',
    transport: 'Transporte',
    payroll: 'Nómina / Agrupación',
    other: 'Otro'
  }.freeze

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :fund_type, presence: true, inclusion: { in: FUND_TYPES }
  validates :currency, presence: true

  def self.fund_label_for(type)
    FUND_TYPE_LABELS[type.to_sym] || 'Otro'
  end

  def fund_label
    self.class.fund_label_for(fund_type)
  end

  has_many :fund_expenses, dependent: :destroy

  def spent_total
    fund_expenses.sum(:amount).to_f
  end

  def remaining
    amount.to_f - spent_total
  end

  # Calcula el saldo disponible de todos los fondos de nómina directamente en SQL,
  # sin cargar ningún registro en memoria Ruby.
  def self.total_payroll_remaining
    result = where(fund_type: 'payroll')
               .left_joins(:fund_expenses)
               .select('COALESCE(SUM(fund_allocations.amount), 0) - COALESCE(SUM(fund_expenses.amount), 0) AS net_remaining')
               .first
    result&.net_remaining.to_f
  end
end
