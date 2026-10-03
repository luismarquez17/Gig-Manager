# frozen_string_literal: true

class GigPayment < ApplicationRecord
  include FinancialAuditable

  belongs_to :gig

  CATEGORIES = %w[reinvest waste other].freeze

  PAYMENT_METHODS = {
    'cash'          => { label: 'Efectivo', emoji: '💵', bg: '#dcfce7', color: '#166534' },
    'zelle'         => { label: 'Zelle', emoji: '⚡', bg: '#ede9fe', color: '#5b21b6' },
    'bank_transfer' => { label: 'Transferencia Bancaria', emoji: '🏦', bg: '#dbeafe', color: '#1e40af' },
    'card_stripe'   => { label: 'Tarjeta / Stripe', emoji: '💳', bg: '#fef3c7', color: '#92400e' },
    'mobile_pay'    => { label: 'Pago Móvil', emoji: '📱', bg: '#ffedd5', color: '#9a3412' },
    'check'         => { label: 'Cheque', emoji: '🧾', bg: '#f1f5f9', color: '#334155' },
    'other'         => { label: 'Otro Método', emoji: '💰', bg: '#f8fafc', color: '#475569' }
  }.freeze

  before_validation :ensure_currency
  before_validation :ensure_payment_method
  before_validation :ensure_receipt_number

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
  validates :payment_method, inclusion: { in: PAYMENT_METHODS.keys }, allow_blank: true
  validate :amount_cannot_exceed_agreed_amount

  scope :recent_first, -> { order(date_paid: :desc, created_at: :desc) }

  def payment_method_label
    PAYMENT_METHODS.dig(payment_method, :label) || payment_method&.humanize || 'Efectivo'
  end

  def payment_method_emoji
    PAYMENT_METHODS.dig(payment_method, :emoji) || '💵'
  end

  def payment_method_badge_bg
    PAYMENT_METHODS.dig(payment_method, :bg) || '#dcfce7'
  end

  def payment_method_badge_color
    PAYMENT_METHODS.dig(payment_method, :color) || '#166534'
  end

  def receipt_display_number
    receipt_number.presence || ensure_receipt_number || "REC-#{id}"
  end

  # Datos calculados para el comprobante oficial
  def previous_payments_sum
    return 0.0 unless gig
    gig.gig_payments.where("created_at < ? OR (created_at = ? AND id < ?)", created_at || Time.current, created_at || Time.current, id || 0).sum(:amount).to_f
  end

  def remaining_after_this_payment
    return 0.0 unless gig
    total_after = previous_payments_sum + amount.to_f
    [gig.amount.to_f - total_after, 0.0].max
  end

  private

  def ensure_currency
    self.currency = 'USD' if currency.blank? || currency != 'USD'
  end

  def ensure_payment_method
    self.payment_method = 'cash' if payment_method.blank?
  end

  def ensure_receipt_number
    return receipt_number if receipt_number.present?

    year = date_paid&.year || Time.current.year
    company_id = gig&.company_id || Current.company&.id

    scope = GigPayment.joins(:gig)
    scope = scope.where(gigs: { company_id: company_id }) if company_id
    scope = scope.where("receipt_number LIKE ?", "REC-#{year}-%")

    max_num = 0
    scope.pluck(:receipt_number).each do |rn|
      if rn =~ /REC-\d{4}-(\d+)/
        val = $1.to_i
        max_num = val if val > max_num
      end
    end

    seq = max_num + 1
    self.receipt_number = format("REC-%d-%05d", year, seq)
  end

  def amount_cannot_exceed_agreed_amount
    return unless gig && amount.present?

    # Sum of other payments for this gig (exclude self if updating)
    other_payments_total = gig.gig_payments.where.not(id: id).sum(:amount).to_f
    if (other_payments_total + amount.to_f) > gig.amount.to_f
      errors.add(:amount, "no puede ser mayor al monto acordado del show (#{gig.amount})")
    end
  end
end
