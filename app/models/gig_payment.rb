class GigPayment < ApplicationRecord
  belongs_to :gig

  CATEGORIES = %w[reinvest waste other].freeze

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true

  validate :amount_cannot_exceed_agreed_amount

  private

  def amount_cannot_exceed_agreed_amount
    return unless gig && amount.present?

    # Sum of other payments for this gig (exclude self if updating)
    other_payments_total = gig.gig_payments.where.not(id: id).sum(:amount).to_f
    if (other_payments_total + amount.to_f) > gig.amount.to_f
      errors.add(:amount, "no puede ser mayor al monto acordado del show (#{gig.amount})")
    end
  end
end
