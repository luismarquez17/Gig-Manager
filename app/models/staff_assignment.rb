class StaffAssignment < ApplicationRecord
  belongs_to :user
  belongs_to :gig

  validates :agreed_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Monto pagado directo registrado para este show específico
  def direct_paid
    return 0.0 unless gig.present? && user.present?
    gig.employee_payments.approved.where(user_id: user_id).sum(:amount).to_f
  end

  # Crédito general aplicado (los créditos/anticipos generales no alteran shows individuales)
  def general_credit_applied
    0.0
  end

  # Total pagado directo registrado para este show
  def total_paid
    direct_paid
  end

  # Saldo neto de este show (Acordado - Total pagado)
  def balance
    (agreed_amount.to_f - total_paid).round(2)
  end

  # Saldo pendiente de cobro de este show (> 0)
  def pending_balance
    [balance, 0.0].max
  end

  # Saldo a favor de la empresa si se le pagó de más en este show
  def worker_owes_company
    diff = total_paid - agreed_amount.to_f
    diff.positive? ? diff.round(2) : 0.0
  end

  def clear_cached_breakdown!
    # No-op para compatibilidad
  end
end
