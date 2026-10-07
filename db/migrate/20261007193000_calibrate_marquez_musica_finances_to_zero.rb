# frozen_string_literal: true

class CalibrateMarquezMusicaFinancesToZero < ActiveRecord::Migration[7.1]
  def up
    company = Company.find_by(slug: 'marquez-musica')
    return unless company.present?

    # Check if calibration already exists
    existing_calibration = company.cash_adjustments.where("description LIKE ?", "%REINICIO Y CALIBRACIÓN CONTABLE 07/10/2026%").exists?
    return if existing_calibration

    total_inflows = GigPayment.joins(:gig).where(gigs: { company_id: company.id }).approved.sum(:amount).to_f +
                    company.cash_adjustments.inflows.sum(:amount).to_f

    payroll_outflows = company.employee_payments.approved.where.not(funding_source: 'external_capital').sum(:amount).to_f
    maintenance_outflows = MaintenanceRecord.joins(:item).where(items: { company_id: company.id }).sum(:cost).to_f
    investment_outflows = company.investments.sum(:amount).to_f
    withdrawal_outflows = company.cash_adjustments.outflows.sum(:amount).to_f

    total_outflows = payroll_outflows + maintenance_outflows + investment_outflows + withdrawal_outflows
    net_balance = (total_inflows - total_outflows).round(2)

    return if net_balance.zero?

    if net_balance.positive?
      company.cash_adjustments.create!(
        amount: net_balance,
        currency: 'USD',
        adjustment_type: :withdrawal,
        date: Date.new(2026, 10, 7),
        description: "[REINICIO Y CALIBRACIÓN CONTABLE 07/10/2026] Calibración de fondo general a $0.00 para inicio de nuevo ciclo operativo",
        status: 'approved'
      )
    else
      company.cash_adjustments.create!(
        amount: net_balance.abs,
        currency: 'USD',
        adjustment_type: :initial_balance,
        date: Date.new(2026, 10, 7),
        description: "[REINICIO Y CALIBRACIÓN CONTABLE 07/10/2026] Calibración de fondo general a $0.00 para inicio de nuevo ciclo operativo",
        status: 'approved'
      )
    end
  end

  def down
    company = Company.find_by(slug: 'marquez-musica')
    return unless company.present?

    company.cash_adjustments.where("description LIKE ?", "%REINICIO Y CALIBRACIÓN CONTABLE 07/10/2026%").destroy_all
  end
end
