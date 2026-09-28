class StaffAssignment < ApplicationRecord
  belongs_to :user
  belongs_to :gig

  validates :agreed_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Monto pagado directo registrado para este show específico
  def direct_paid
    return 0.0 unless gig.present? && user.present?
    gig.employee_payments.approved.where(user_id: user_id).sum(:amount).to_f
  end

  # Crédito general aplicado (de pagos generales, anticipos o ajustes sin show)
  def general_credit_applied
    compute_balance_breakdown[:credit_applied]
  end

  # Total pagado efectivo = pagos directos + créditos generales aplicados a este show
  def total_paid
    compute_balance_breakdown[:total_paid]
  end

  # Saldo neto (Acordado - Total pagado)
  def balance
    compute_balance_breakdown[:balance]
  end

  # Saldo pendiente de cobro (> 0)
  def pending_balance
    compute_balance_breakdown[:pending_balance]
  end

  # Saldo a favor de la empresa si se le pagó de más en este show
  def worker_owes_company
    compute_balance_breakdown[:worker_owes]
  end

  def clear_cached_breakdown!
    @compute_balance_breakdown = nil
  end

  private

  def compute_balance_breakdown
    @compute_balance_breakdown ||= begin
      agreed = agreed_amount.to_f
      return { direct_paid: 0.0, credit_applied: 0.0, total_paid: 0.0, balance: agreed, pending_balance: agreed, worker_owes: 0.0 } unless gig.present? && user.present?

      direct = gig.employee_payments.approved.where(user_id: user_id).sum(:amount).to_f

      if direct >= agreed
        {
          direct_paid: direct,
          credit_applied: 0.0,
          total_paid: direct,
          balance: (agreed - direct).round(2),
          pending_balance: 0.0,
          worker_owes: (direct - agreed).round(2)
        }
      else
        all_worker_assignments = user.staff_assignments.includes(:gig)
          .select { |sa| sa.gig.present? }
          .sort_by { |sa| [sa.gig.date || Date.today, sa.created_at || Time.current] }

        all_worker_payments = user.employee_payments.approved.to_a
        
        # Créditos de pagos generales / anticipos (gig_id: nil)
        net_standalone_credits = all_worker_payments
          .select { |p| p.gig_id.nil? }
          .sum { |p| p.amount.to_f - p.expected_amount.to_f }

        available_credit = [net_standalone_credits, 0.0].max
        applied_to_this = 0.0

        paid_by_gig_map = all_worker_payments.reject { |p| p.gig_id.nil? }.group_by(&:gig_id)

        all_worker_assignments.each do |sa|
          sa_direct = (paid_by_gig_map[sa.gig_id] || []).sum { |p| p.amount.to_f }
          sa_agreed = sa.agreed_amount.to_f

          if sa_direct > sa_agreed
            available_credit += (sa_direct - sa_agreed)
          elsif sa_direct < sa_agreed
            sa_needed = sa_agreed - sa_direct
            portion = [available_credit, sa_needed].min
            available_credit -= portion
            if sa.id == self.id
              applied_to_this = portion
              break
            end
          elsif sa.id == self.id
            break
          end
        end

        total_effective = (direct + applied_to_this).round(2)
        rem_balance = (agreed - total_effective).round(2)

        {
          direct_paid: direct,
          credit_applied: applied_to_this.round(2),
          total_paid: total_effective,
          balance: rem_balance,
          pending_balance: [rem_balance, 0.0].max.round(2),
          worker_owes: 0.0
        }
      end
    end
  end
end
