class EmployeePayment < ApplicationRecord
  include TenantScoped
  include FinancialAuditable

  FUNDING_SOURCES = %w[payroll_fund external_capital].freeze
  STATUSES = %w[approved pending_approval rejected voided].freeze

  attribute :funding_source, :string, default: 'payroll_fund'
  attribute :external_source_name, :string
  attribute :status, :string, default: 'approved'
  attribute :reported_by_worker, :boolean, default: false

  belongs_to :user
  belongs_to :gig, optional: true
  belongs_to :voided_by, class_name: 'User', optional: true
  has_many :fund_expenses, dependent: :destroy

  before_validation :ensure_expected_amount
  before_validation :set_default_funding_source
  before_validation :set_default_status
  before_validation :ensure_currency
  before_validation :ensure_receipt_number, if: :approved?

  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :expected_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :amount_or_expected_amount_positive
  validates :funding_source, inclusion: { in: FUNDING_SOURCES }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  scope :approved, -> { where(status: 'approved') }
  scope :pending_approval, -> { where(status: 'pending_approval') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :voided, -> { where(status: 'voided') }
  scope :active_records, -> { where.not(status: 'voided') }

  def approved?
    status == 'approved'
  end

  def pending_approval?
    status == 'pending_approval'
  end

  def rejected?
    status == 'rejected'
  end

  def voided?
    status == 'voided'
  end

  def void!(reason, user = nil)
    self.status = 'voided'
    self.voided_at = Time.current
    self.void_reason = reason.presence || 'Anulación contable por el usuario'
    self.voided_by = user if user.present?
    self.audit_reason = "Anulación de pago a trabajador: #{self.void_reason}"
    save!
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
    when 'voided'
      'Anulado'
    else
      status.to_s.humanize
    end
  end

  def status_badge_bg
    case status
    when 'approved'         then '#dcfce7'
    when 'pending_approval' then '#fef3c7'
    when 'rejected'         then '#fee2e2'
    when 'voided'           then '#fee2e2'
    else '#f1f5f9'
    end
  end

  def status_badge_color
    case status
    when 'approved'         then '#166534'
    when 'pending_approval' then '#92400e'
    when 'rejected'         then '#991b1b'
    when 'voided'           then '#991b1b'
    else '#475569'
    end
  end

  def status_emoji
    case status
    when 'approved'         then '✅'
    when 'pending_approval' then '⏳'
    when 'rejected'         then '❌'
    when 'voided'           then '🚫'
    else '📄'
    end
  end

  def receipt_display_number
    receipt_number.presence || (approved? ? ensure_receipt_number : "EP-PENDIENTE")
  end

  def whatsapp_receipt_text(receipt_url = nil)
    comp_name = company&.name.presence || gig&.company&.name.presence || "Gig Manager"
    w_name = user&.display_name.presence || user&.name.presence || "Trabajador"
    dt = date_paid ? date_paid.strftime('%d/%m/%Y') : Date.today.strftime('%d/%m/%Y')
    amt = sprintf('%.2f', amount.to_f)
    curr = currency.presence || 'USD'
    f_num = receipt_display_number
    pm_label = payment_method.presence || "Efectivo"
    
    show_desc = if gig.present?
      c_name = gig.client_display_name
      g_dt = gig.date ? gig.date.strftime('%d/%m/%Y') : 'Fecha por confirmar'
      "#{c_name} (#{g_dt})"
    else
      "Abono / Anticipo General"
    end

    lines = [
      "🧾 *COMPROBANTE DE PAGO DE NÓMINA - #{comp_name.upcase}*",
      "─────────────────────────",
      "📄 *Folio:* #{f_num}",
      "👤 *Personal / Músico:* #{w_name}",
      "📅 *Fecha:* #{dt}",
      "🎵 *Concepto / Evento:* #{show_desc}",
      "💵 *Monto Pagado:* $#{amt} #{curr}",
      "💳 *Forma de Pago:* #{pm_label}",
      "─────────────────────────"
    ]

    if user.present?
      w_balance = user.pending_balance
      bal_str = sprintf('%.2f', [w_balance, 0.0].max)
      lines << "📊 *Saldo Pendiente Restante:* $#{bal_str} #{curr}"
      lines << "─────────────────────────"
    end

    if receipt_url.present?
      lines << "🔗 *Ver Comprobante Digital:* #{receipt_url}"
    end

    lines.join("\n")
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

  def ensure_currency
    self.currency = 'USD' if currency.blank? || currency != 'USD'
  end

  def ensure_receipt_number
    return receipt_number if receipt_number.present?
    return unless approved?

    year = date_paid&.year || Time.current.year
    cid = company_id || gig&.company_id || Current.company&.id

    scope = EmployeePayment.all
    scope = scope.where(company_id: cid) if cid
    scope = scope.where("receipt_number LIKE ?", "EP-#{year}-%")

    max_num = 0
    scope.pluck(:receipt_number).each do |rn|
      if rn =~ /EP-\d{4}-(\d+)/
        val = $1.to_i
        max_num = val if val > max_num
      end
    end

    seq = max_num + 1
    self.receipt_number = format("EP-%d-%05d", year, seq)
  end

  def amount_or_expected_amount_positive
    if amount.to_f <= 0 && expected_amount.to_f <= 0
      errors.add(:amount, "debe ser mayor a 0 o tener un monto esperado mayor a 0")
    end
  end
end
