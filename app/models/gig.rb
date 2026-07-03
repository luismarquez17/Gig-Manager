class Gig < ApplicationRecord
  belongs_to :client, optional: true
  has_many :gig_items, dependent: :destroy
  has_many :items, through: :gig_items
  has_many :staff_assignments, dependent: :destroy
  has_many :staff_members, through: :staff_assignments, source: :user
  has_many :gig_payments, dependent: :destroy
  has_many :employee_payments, dependent: :nullify
  has_many :fund_allocations, dependent: :destroy
  has_many :gig_timeline_items, dependent: :destroy
  
  validates :amount, presence: true
  validates :client_email, presence: true, if: -> { client_id.blank? }
  validates :client_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  before_validation :copy_client_email
  before_create :generate_portal_token

  # Financial helpers
  def total_received
    gig_payments.sum(:amount)
  end

  def total_employee_payouts
    employee_payments.sum(:amount)
  end

  def total_allocated
    fund_allocations.sum(:amount)
  end

  def payroll_allocations
    fund_allocations.where(fund_type: 'payroll')
  end

  def total_payroll_remaining
    payroll_allocations.sum { |allocation| allocation.remaining.to_f }
  end

  def remaining_amount
    amount.to_f - total_received.to_f
  end

  def event_duration
    return nil unless start_time.present? && end_time.present?
    diff_seconds = end_time - start_time
    diff_seconds += 86400 if diff_seconds < 0 # Handle crossing midnight
    (diff_seconds / 3600.0).round(1)
  end

  def formatted_time_range
    return nil unless start_time.present? && end_time.present?
    start_str = start_time.strftime("%I:%M %p")
    end_str = end_time.strftime("%I:%M %p")
    duration = event_duration
    duration_str = duration == duration.to_i ? "#{duration.to_i} horas" : "#{duration} horas"
    "#{start_str} → #{end_str} · #{duration_str}"
  end

  def payment_status
    if total_received.to_f.zero?
      :unpaid
    elsif remaining_amount.positive?
      :partial
    else
      :paid
    end
  end

  def payment_status_label
    case payment_status
    when :paid
      'Pagado'
    when :partial
      'Parcial'
    else
      'Pendiente'
    end
  end

  def payment_status_badge_class
    case payment_status
    when :paid
      'bg-success'
    when :partial
      'bg-warning'
    else
      'bg-danger'
    end
  end

  def remaining_balance
    (total_received || 0) - (total_allocated || 0)
  end

  def portal_token
    token = read_attribute(:portal_token)
    if token.blank?
      token = SecureRandom.hex(16)
      update_columns(portal_token: token) if persisted?
    end
    token
  end

  # Se ejecuta al crear, editar o borrar un show
  after_save :refresh_client_priority
  after_destroy :refresh_client_priority

  private

  def copy_client_email
    if client_id.present? && client_email.blank?
      self.client_email = client&.email
    end
  end

  def refresh_client_priority
    # Usamos &. para evitar errores si por alguna razón el cliente es nil
    client&.update_priority!
  end

  def generate_portal_token
    self.portal_token ||= SecureRandom.hex(16)
  end
end