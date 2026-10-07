class CashAdjustment < ApplicationRecord
  include TenantScoped
  include FinancialAuditable

  belongs_to :company
  belongs_to :user, optional: true
  belongs_to :voided_by, class_name: 'User', optional: true

  enum adjustment_type: {
    deposit: 0,
    withdrawal: 1,
    initial_balance: 2
  }

  before_validation { self.currency = 'USD' if currency.blank? || currency != 'USD' }
  before_validation { self.status = 'approved' if status.blank? }

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true
  validates :description, presence: true
  validates :currency, presence: true

  scope :recent_first, -> { order(date: :desc, created_at: :desc) }
  scope :approved, -> { where(status: 'approved') }
  scope :voided, -> { where(status: 'voided') }
  scope :active_records, -> { where.not(status: 'voided') }
  scope :inflows, -> { where(adjustment_type: [:deposit, :initial_balance]).where(status: 'approved') }
  scope :outflows, -> { where(adjustment_type: :withdrawal).where(status: 'approved') }

  def approved?
    status == 'approved'
  end

  def voided?
    status == 'voided'
  end

  def void!(reason, current_user = nil)
    self.status = 'voided'
    self.voided_at = Time.current
    self.void_reason = reason.presence || 'Anulación contable por el usuario'
    self.voided_by = current_user if current_user.present?
    self.audit_reason = "Anulación de movimiento de caja: #{self.void_reason}"
    save!
  end

  def inflow?
    deposit? || initial_balance?
  end

  def outflow?
    withdrawal?
  end

  def signed_amount
    inflow? ? amount.to_f : -amount.to_f
  end

  def type_label
    case adjustment_type.to_s
    when 'deposit', 'initial_balance'
      'Ingreso a Caja'
    when 'withdrawal'
      'Retiro de Caja'
    else
      adjustment_type.to_s.humanize
    end
  end

  def type_badge_bg
    case adjustment_type.to_s
    when 'deposit', 'initial_balance'
      '#dcfce7'
    when 'withdrawal'
      '#fee2e2'
    else
      '#f1f5f9'
    end
  end

  def type_badge_color
    case adjustment_type.to_s
    when 'deposit', 'initial_balance'
      '#166534'
    when 'withdrawal'
      '#991b1b'
    else
      '#334155'
    end
  end

  def type_emoji
    case adjustment_type.to_s
    when 'deposit', 'initial_balance'
      '💵'
    when 'withdrawal'
      '💸'
    else
      '💰'
    end
  end
end
