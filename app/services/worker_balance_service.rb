# frozen_string_literal: true

class WorkerBalanceService
  attr_reader :worker, :worker_payments, :worker_assignments, :agreed_total, :paid_total, :payment_count, :today

  def initialize(worker:, worker_payments: [], worker_assignments: [], agreed_total: nil, paid_total: nil, payment_count: nil, today: Date.today)
    @worker             = worker
    @worker_payments    = worker_payments || []
    @worker_assignments = worker_assignments || []
    @agreed_total       = (agreed_total || @worker_assignments.sum { |sa| sa.agreed_amount.to_f }).to_f
    @paid_total         = (paid_total || @worker_payments.select(&:approved?).sum { |p| p.amount.to_f }).to_f
    @payment_count      = payment_count || @worker_payments.count(&:approved?)
    @today              = today
  end

  def self.build_metrics_for_company(company)
    workers = company.users.workers.order(:email)
    worker_ids = workers.pluck(:id)

    staff_agreed_sums = StaffAssignment.where(user_id: worker_ids).group(:user_id).sum(:agreed_amount)
    paid_sums         = company.employee_payments.approved.where(user_id: worker_ids).group(:user_id).sum(:amount)
    counts            = company.employee_payments.approved.where(user_id: worker_ids).group(:user_id).count

    assignments_by_worker = StaffAssignment
      .where(user_id: worker_ids)
      .includes(gig: :client)
      .group_by(&:user_id)

    all_approved_payments = company.employee_payments.approved.where(user_id: worker_ids).includes(:gig)
    payments_by_worker    = all_approved_payments.group_by(&:user_id)

    today = Date.today

    workers.map do |worker|
      new(
        worker:             worker,
        worker_payments:    payments_by_worker[worker.id] || [],
        worker_assignments: assignments_by_worker[worker.id] || [],
        agreed_total:       staff_agreed_sums[worker.id].to_f,
        paid_total:         paid_sums[worker.id].to_f,
        payment_count:      counts[worker.id] || 0,
        today:              today
      ).to_h
    end
  end

  def to_h
    {
      worker:         worker,
      total_paid:     paid_total,
      agreed_amount:  agreed_total,
      balance:        balance,
      past_balance:   past_balance,
      future_balance: future_balance,
      overpaid:       overpaid,
      payment_count:  payment_count,
      gig_debts:      gig_debts,
      future_gigs:    future_gigs
    }
  end

  def balance
    agreed_total - paid_total
  end

  def paid_by_gig
    @paid_by_gig ||= worker_payments.group_by(&:gig_id).transform_values { |ps| ps.sum { |p| p.amount.to_f } }
  end

  def past_assignments
    @past_assignments ||= worker_assignments
      .select { |sa| sa.gig.present? && sa.gig.date.present? && sa.gig.date <= today }
      .sort_by { |sa| sa.gig.date || today }
  end

  def raw_past_balance
    @raw_past_balance ||= past_assignments.sum do |sa|
      unpaid = sa.agreed_amount.to_f - paid_by_gig[sa.gig_id].to_f
      unpaid.positive? ? unpaid : 0
    end
  end

  def net_adjustment_credits
    @net_adjustment_credits ||= worker_payments
      .select { |p| p.gig_id.nil? }
      .sum { |p| p.amount.to_f - p.expected_amount.to_f }
  end

  def past_balance
    net = raw_past_balance - net_adjustment_credits
    net >= 0 ? net.round(2) : 0.0
  end

  def gig_debts
    @gig_debts ||= begin
      remaining_credit = [net_adjustment_credits, 0].max
      debts = []

      past_assignments.each do |sa|
        paid_for_gig   = paid_by_gig[sa.gig_id].to_f
        pending_raw    = sa.agreed_amount.to_f - paid_for_gig
        next if pending_raw <= 0

        credit_applied    = [remaining_credit, pending_raw].min
        effective_pending = (pending_raw - credit_applied).round(2)
        remaining_credit  -= credit_applied

        next if effective_pending <= 0

        debts << {
          gig:            sa.gig,
          agreed_amount:  sa.agreed_amount.to_f,
          paid_amount:    paid_for_gig + credit_applied,
          pending_amount: effective_pending,
          type:           :assignment
        }
      end

      if net_adjustment_credits < 0
        debts << {
          gig:            nil,
          agreed_amount:  0.0,
          paid_amount:    0.0,
          pending_amount: -net_adjustment_credits,
          type:           :adjustment,
          title:          "Ajustes contables del Líder (Cargo adicional)"
        }
      end

      assigned_gig_ids = worker_assignments.map(&:gig_id)
      standalone_payments = worker_payments.reject { |p| assigned_gig_ids.include?(p.gig_id) }
      standalone_by_gig   = standalone_payments.group_by(&:gig_id)

      standalone_by_gig.each do |_gig_id, ps|
        paid_for_gig = ps.sum { |p| p.amount.to_f }
        expected     = ps.map { |p| p.expected_amount.to_f }.max || 0.0
        pending      = expected - paid_for_gig
        next if pending <= 0

        debts << {
          gig:            ps.first.gig,
          agreed_amount:  expected,
          paid_amount:    paid_for_gig,
          pending_amount: pending,
          type:           :standalone
        }
      end

      debts.sort_by { |d| d[:gig]&.date || today }.reverse
    end
  end

  def overpaid
    @overpaid ||= worker_assignments.sum do |sa|
      next 0 unless sa.gig.present? && sa.gig.date.present? && sa.gig.date <= today

      excess = paid_by_gig[sa.gig_id].to_f - sa.agreed_amount.to_f
      excess.positive? ? excess : 0
    end
  end

  def future_balance
    @future_balance ||= worker_assignments.sum do |sa|
      next 0 unless sa.gig.present? && sa.gig.date.present? && sa.gig.date > today

      unpaid = sa.agreed_amount.to_f - paid_by_gig[sa.gig_id].to_f
      unpaid.positive? ? unpaid : 0
    end
  end

  def future_gigs
    @future_gigs ||= worker_assignments.filter_map do |sa|
      next if sa.gig.blank? || sa.gig.date.blank? || sa.gig.date <= today

      paid_for_gig = paid_by_gig[sa.gig_id].to_f
      pending      = sa.agreed_amount.to_f - paid_for_gig
      next if pending <= 0

      {
        gig:            sa.gig,
        agreed_amount:  sa.agreed_amount.to_f,
        paid_amount:    paid_for_gig,
        pending_amount: pending
      }
    end.sort_by { |d| d[:gig]&.date || today }
  end
end
