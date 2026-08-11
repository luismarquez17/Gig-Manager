class EmployeePayment < ApplicationRecord
  include TenantScoped

  FUNDING_SOURCES = %w[payroll_fund external_capital].freeze
  STATUSES = %w[approved pending_approval rejected].freeze

  attribute :funding_source, :string, default: 'payroll_fund'
  attribute :external_source_name, :string
  attribute :status, :string, default: 'approved'
  attribute :reported_by_worker, :boolean, default: false

  belongs_to :user
  belongs_to :gig, optional: true
  has_many :fund_expenses, dependent: :destroy

  before_validation :ensure_expected_amount
  before_validation :set_default_funding_source
  before_validation :set_default_status

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :expected_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :funding_source, inclusion: { in: FUNDING_SOURCES }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  scope :approved, -> { where(status: 'approved') }
  scope :pending_approval, -> { where(status: 'pending_approval') }
  scope :rejected, -> { where(status: 'rejected') }

  def approved?
    status == 'approved'
  end

  def pending_approval?
    status == 'pending_approval'
  end

  def rejected?
    status == 'rejected'
  end

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

  def status_label
    case status
    when 'approved'
      'Confirmado'
    when 'pending_approval'
      'Pendiente de Aprobación'
    when 'rejected'
      'Rechazado'
    else
      status.to_s.humanize
    end
  end

  private

  def set_default_status
    self.status = 'approved' if status.blank?
  end

  def set_default_funding_source
    self.funding_source = 'payroll_fund' if funding_source.blank?
  end

  def ensure_expected_amount
    self.expected_amount = 0.0 if expected_amount.nil? || expected_amount.to_s.blank?
  end
end
