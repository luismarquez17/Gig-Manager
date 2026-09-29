class StandardizeCurrencyToUsdAndFixMarquezMusicaFund < ActiveRecord::Migration[7.1]
  def up
    # 1. Corregir cualquier pago a trabajador aberrante por confusión de Bolívares (ej: 30000 Bs -> $30.00 USD)
    if table_exists?(:employee_payments)
      execute <<-SQL
        UPDATE employee_payments
        SET amount = 30.0, notes = COALESCE(notes, '') || ' [Corregido de 30000 Bs a $30.00 USD]'
        WHERE amount >= 1000 AND (amount = 30000 OR currency = 'BS' OR notes ILIKE '%30000%' OR notes ILIKE '%bs%');
      SQL

      execute <<-SQL
        UPDATE employee_payments
        SET currency = 'USD'
        WHERE currency != 'USD' OR currency IS NULL;
      SQL
    end

    # 2. Estandarizar todas las tablas a USD
    %i[
      gigs
      gig_payments
      investments
      shopping_items
      preset_budgets
      client_quotes
      cash_adjustments
      companies
      standard_upsells
      gig_upsell_requests
      fund_allocations
      fund_expenses
    ].each do |tbl|
      next unless table_exists?(tbl)
      if column_exists?(tbl, :currency)
        execute "UPDATE #{tbl} SET currency = 'USD' WHERE currency != 'USD' OR currency IS NULL;"
      end
    end

    # 3. Calibrar el fondo de Márquez Música exactamente a $120.00 USD
    company = Company.find_by(slug: 'marquez-musica') ||
              Company.where("LOWER(name) LIKE ?", "%marquez%").first ||
              Company.find_by(id: 1)

    if company.present?
      # Inflows
      gigs_received = GigPayment.joins(:gig).where(gigs: { company_id: company.id }).sum(:amount).to_f
      cash_deposits = company.cash_adjustments.inflows.sum(:amount).to_f
      total_inflow  = (gigs_received + cash_deposits).round(2)

      # Outflows
      payroll_paid     = company.employee_payments.approved.sum(:amount).to_f
      maintenance_cost = MaintenanceRecord.joins(:item).where(items: { company_id: company.id }).sum(:cost).to_f
      investments_cost = company.investments.sum(:amount).to_f
      cash_withdrawals = company.cash_adjustments.outflows.sum(:amount).to_f
      total_outflow    = (payroll_paid + maintenance_cost + investments_cost + cash_withdrawals).round(2)

      current_fund_balance = (total_inflow - total_outflow).round(2)
      target_balance = 120.00
      diff = (target_balance - current_fund_balance).round(2)

      leader_user = company.users.where(role: 'leader').first || company.users.first

      if diff > 0
        company.cash_adjustments.create!(
          user: leader_user,
          adjustment_type: 'deposit',
          amount: diff,
          currency: 'USD',
          date: Date.today,
          description: "Calibración inicial de fondo de reserva a $120.00 USD"
        )
      elsif diff < 0
        company.cash_adjustments.create!(
          user: leader_user,
          adjustment_type: 'withdrawal',
          amount: -diff,
          currency: 'USD',
          date: Date.today,
          description: "Calibración inicial de fondo de reserva a $120.00 USD"
        )
      end
    end
  end

  def down
    # No-op rollback
  end
end
