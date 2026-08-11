class EmployeePayment < ApplicationRecord
  include TenantScoped

  FUNDING_SOURCES = %w[payroll_fund external_capital].freeze

  attribute :funding_source, :string, default: 'payroll_fund'
  attribute :external_source_name, :string

  belongs_to :user
  belongs_to :gig, optional: true
  has_many :fund_expenses, dependent: :destroy

  before_validation :ensure_expected_amount
  before_validation :set_default_funding_source

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :expected_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :funding_source, inclusion: { in: FUNDING_SOURCES }, allow_nil: true

  def from_external_capital?
    funding_source == 'external_capital'
  end

  def from_payroll_fund?
    !from_external_capital?
  end

  def funding_source_label
    if from_external_capital?
      external_source_name.presence || "Capital externo (Dinero personal del leader)"
    else
      "Fondo de Nómina / Agrupación"
    end
  end

  private

  def set_default_funding_source
    self.funding_source = 'payroll_fund' if funding_source.blank?
  end

  def ensure_expected_amount
    self.expected_amount = 0.0 if expected_amount.nil? || expected_amount.to_s.blank?
  end
end
