# frozen_string_literal: true

namespace :marquez do
  desc "Calibra el fondo de caja de Marquez Musica a $0.00 como punto de partida sin alterar registros ni deudas"
  task calibrate_finances_to_zero: :environment do
    company = Company.find_by(slug: 'marquez-musica')
    unless company.present?
      puts "Empresa marquez-musica no encontrada."
      next
    end

    total_inflows = GigPayment.joins(:gig).where(gigs: { company_id: company.id }).approved.sum(:amount).to_f +
                    company.cash_adjustments.inflows.sum(:amount).to_f

    payroll_outflows = company.employee_payments.approved.where.not(funding_source: 'external_capital').sum(:amount).to_f
    maintenance_outflows = MaintenanceRecord.joins(:item).where(items: { company_id: company.id }).sum(:cost).to_f
    investment_outflows = company.investments.sum(:amount).to_f
    withdrawal_outflows = company.cash_adjustments.outflows.sum(:amount).to_f

    total_outflows = payroll_outflows + maintenance_outflows + investment_outflows + withdrawal_outflows
    net_balance = (total_inflows - total_outflows).round(2)

    puts "Total Inflows: $#{total_inflows}"
    puts "Total Outflows: $#{total_outflows}"
    puts "Net Balance actual: $#{net_balance}"

    if net_balance.zero?
      puts "El saldo de caja ya está exactamente en $0.00."
    elsif net_balance.positive?
      adj = company.cash_adjustments.create!(
        amount: net_balance,
        currency: 'USD',
        adjustment_type: :withdrawal,
        date: Date.new(2026, 10, 7),
        description: "[REINICIO Y CALIBRACIÓN CONTABLE 07/10/2026] Calibración de fondo general a $0.00 para inicio de nuevo ciclo operativo",
        status: 'approved'
      )
      puts "✅ Creado retiro de calibración: #{adj.id} por $#{adj.amount}. Nuevo saldo: $0.00"
    else
      adj = company.cash_adjustments.create!(
        amount: net_balance.abs,
        currency: 'USD',
        adjustment_type: :initial_balance,
        date: Date.new(2026, 10, 7),
        description: "[REINICIO Y CALIBRACIÓN CONTABLE 07/10/2026] Calibración de fondo general a $0.00 para inicio de nuevo ciclo operativo",
        status: 'approved'
      )
      puts "✅ Creado ajuste de balance inicial: #{adj.id} por $#{adj.amount}. Nuevo saldo: $0.00"
    end
  end
end
