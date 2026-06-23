class Gig < ApplicationRecord
  belongs_to :client
  has_many :gig_items, dependent: :destroy
  has_many :items, through: :gig_items
  has_many :staff_assignments, dependent: :destroy
  has_many :staff_members, through: :staff_assignments, source: :user
  has_many :gig_payments, dependent: :destroy
  has_many :employee_payments, dependent: :nullify
  has_many :fund_allocations, dependent: :destroy
  validates :amount, presence: true

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

  def remaining_balance
    (total_received || 0) - (total_employee_payouts || 0) - (total_allocated || 0)
  end

  # Se ejecuta al crear, editar o borrar un show
  after_save :refresh_client_priority
  after_destroy :refresh_client_priority

  private

  def refresh_client_priority
    # Usamos &. para evitar errores si por alguna razón el cliente es nil
    client&.update_priority!
  end
end