class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:terms, :privacy, :suspended], raise: false
  skip_before_action :set_current_tenant, only: [:terms, :privacy, :suspended], raise: false
  skip_before_action :check_company_subscription!, only: [:terms, :privacy, :suspended], raise: false

  before_action :require_leader!, only: [:availability, :financials]
  before_action -> { require_module!(:finances) }, only: [:financials]
  before_action -> { require_module!(:inventory) }, only: [:availability]

  def dashboard
    if current_user.leader? || current_user.superadmin?
      # Consolidamos las 3 queries de InventoryItem en UNA sola con group
      inventory_counts = InventoryItem.joins(:item)
                                      .where(items: { company_id: current_company.id })
                                      .group(:status)
                                      .count
      @total_items   = inventory_counts.values.sum
      @items_danados = inventory_counts['damaged'].to_i
      @items_excelente = inventory_counts['available'].to_i

      # Fusionamos el conteo total y el de próximos gigs en una query
      gigs_scope = current_company.gigs
      @total_gigs           = gigs_scope.count
      @upcoming_gigs_count  = gigs_scope.where("date >= ?", Date.today).count
      @proximos_gigs        = gigs_scope.where("date >= ?", Date.today).order(date: :asc).limit(5)
      @total_clients        = current_company.clients.count

      # Flujo de Caja Real (Fondo de la Banda / Universal)
      @financial_scope = params[:scope].presence || params[:financial_scope].presence || (current_company.financial_reset_active? ? 'current_cycle' : 'all_time')
      reset_date = current_company.effective_reset_date

      if @financial_scope == 'current_cycle' && reset_date.present?
        @total_received          = GigPayment.joins(:gig).where(gigs: { company_id: current_company.id }).where("gigs.date >= ? OR gig_payments.date_paid >= ?", reset_date, reset_date).approved.sum(:amount).to_f
        @total_cash_deposits     = current_company.cash_adjustments.where("date >= ?", reset_date).inflows.sum(:amount).to_f
        @total_inflow            = (@total_received + @total_cash_deposits).round(2)

        payroll_scope            = current_company.employee_payments.approved.where.not(funding_source: 'external_capital').where.not(payment_method: 'Ajuste contable').joins(:gig).where("gigs.date >= ?", reset_date)
        @total_payroll_paid      = payroll_scope.sum(:amount).to_f
        @total_payroll_from_fund = @total_payroll_paid
        @total_maintenance_spent = MaintenanceRecord.joins(:item).where(items: { company_id: current_company.id }).where("maintenance_records.completed_at >= ? OR maintenance_records.created_at >= ?", reset_date, reset_date.beginning_of_day).sum(:cost).to_f
        @total_investments_spent = current_company.investments.where("investments.date >= ? OR investments.created_at >= ?", reset_date, reset_date.beginning_of_day).sum(:amount).to_f
        @total_cash_withdrawals  = current_company.cash_adjustments.where("date >= ?", reset_date).outflows.sum(:amount).to_f
        @total_expenses          = (@total_payroll_from_fund + @total_maintenance_spent + @total_investments_spent + @total_cash_withdrawals).round(2)

        @universal_fund_balance  = (@total_inflow - @total_expenses).round(2)

        cycle_gigs = current_company.gigs.where("date >= ?", reset_date).includes(:gig_payments)
        @total_client_receivables = cycle_gigs.sum { |g| [g.amount.to_f - g.gig_payments.select(&:approved?).sum(&:amount).to_f, 0.0].max }
      else
        @total_received          = GigPayment.joins(:gig).where(gigs: { company_id: current_company.id }).approved.sum(:amount).to_f
        @total_cash_deposits     = current_company.cash_adjustments.inflows.sum(:amount).to_f
        @total_inflow            = (@total_received + @total_cash_deposits).round(2)

        @total_payroll_paid      = current_company.employee_payments.approved.where.not(payment_method: 'Ajuste contable').sum(:amount).to_f
        @total_payroll_from_fund = current_company.employee_payments.approved.where.not(funding_source: 'external_capital').where.not(payment_method: 'Ajuste contable').sum(:amount).to_f
        @total_maintenance_spent = MaintenanceRecord.joins(:item).where(items: { company_id: current_company.id }).sum(:cost).to_f
        @total_investments_spent = current_company.investments.sum(:amount).to_f
        @total_cash_withdrawals  = current_company.cash_adjustments.outflows.sum(:amount).to_f
        @total_expenses          = (@total_payroll_from_fund + @total_maintenance_spent + @total_investments_spent + @total_cash_withdrawals).round(2)

        @universal_fund_balance  = (@total_inflow - @total_expenses).round(2)

        all_gigs = current_company.gigs.includes(:gig_payments)
        @total_client_receivables = all_gigs.sum { |g| [g.amount.to_f - g.gig_payments.select(&:approved?).sum(&:amount).to_f, 0.0].max }
      end

      # Deudas y compromisos con trabajadores (Se preservan 100% intactas)
      @worker_metrics = WorkerBalanceService.build_metrics_for_company(current_company)
      @total_pending_worker_payments = @worker_metrics.sum { |m| m[:past_balance] }
      @total_worker_owes = @worker_metrics.sum { |m| m[:overpaid] }

      @pending_worker_reports = current_company.employee_payments.pending_approval.includes(:user, :gig).order(created_at: :desc)
      @pending_upsell_requests = current_company.gig_upsell_requests.pending.includes(:gig).order(created_at: :desc)
    elsif current_user.staff?
      @proximos_gigs = current_user.assigned_gigs.includes(:gig_items, :client).where("date >= ?", Date.today).order(date: :asc).limit(10)
      gig_ids = @proximos_gigs.pluck(:id)

      # GigItems pendientes de carga (loaded_quantity == 0)
      @pending_gig_items = GigItem.includes(:item, gig: :client).where(gig_id: gig_ids).where(loaded_quantity: 0)
      @items_to_load_count = @pending_gig_items.sum(:quantity)

      # Discrepancias entre lo cargado y lo devuelto
      @discrepant_gig_items = GigItem.where(gig_id: gig_ids)
                                     .where("loaded_quantity IS NOT NULL AND returned_quantity IS NOT NULL AND loaded_quantity != returned_quantity")
      @discrepant_count = @discrepant_gig_items.count

      # Pagos y deudas del staff
      @employee_payments = current_user.employee_payments.includes(:gig).order(created_at: :desc)
      @total_owed = current_user.pending_balance
    elsif current_user.musician?
      @assigned_gigs = current_user.assigned_gigs.includes(:client).order(date: :desc)
      @proximos_gigs = current_user.assigned_gigs.includes(:client).where("date >= ?", Date.today).order(date: :asc)
      @next_gig = @proximos_gigs.first

      # Pagos y deudas del músico
      @employee_payments = current_user.employee_payments.includes(:gig).order(created_at: :desc)
      @total_owed = current_user.pending_balance
    else
      # Client
      client_id = current_user.client_id
      @proximos_gigs = client_id.present? ? Gig.where(client_id: client_id).where("date >= ?", Date.today).order(date: :asc).limit(5) : []
      @mis_presupuestos = if client_id.present? && current_company.present?
        current_company.client_quotes.where("client_id = ? OR client_email = ?", client_id, current_user.email).recent_first.limit(5)
      elsif current_company.present?
        current_company.client_quotes.where(client_email: current_user.email).recent_first.limit(5)
      else
        ClientQuote.none
      end
    end
  end

  def availability
    window_start = Date.today - 7.days
    relevant_gigs = current_company.gigs.where("date >= ?", window_start)
    dates = relevant_gigs.pluck(:date).uniq.compact.sort

    @conflicts = []

    dates.each do |date|
      gig_items_on_date = GigItem.joins(:gig).where(gigs: { company_id: current_company.id, date: date })
      sums = gig_items_on_date.group(:item_id).sum(:quantity)

      sums.each do |item_id, total_requested|
        item = current_company.items.find_by(id: item_id)
        next unless item

        if total_requested > item.available_count
          gigs_involved = relevant_gigs.joins(:gig_items).where(date: date, gig_items: { item_id: item_id })
          @conflicts << {
            date: date,
            item: item,
            requested: total_requested,
            available: item.available_count,
            gigs: gigs_involved
          }
        end
      end
    end
  end

  def financials
    @financial_scope = params[:scope].presence || params[:financial_scope].presence || (current_company.financial_reset_active? ? 'current_cycle' : 'all_time')
    reset_date = current_company.effective_reset_date

    if @financial_scope == 'current_cycle' && reset_date.present?
      company_gigs = current_company.gigs.where("date >= ?", reset_date)
      company_gig_payments = GigPayment.joins(:gig).where(gigs: { company_id: current_company.id }).where("gigs.date >= ? OR gig_payments.date_paid >= ?", reset_date, reset_date).approved

      # 1. Cobros en USD (Moneda única del sistema)
      @total_received_usd  = company_gig_payments.sum(:amount).to_f
      @total_cash_deposits = current_company.cash_adjustments.where("date >= ?", reset_date).inflows.sum(:amount).to_f
      @total_inflow_usd    = (@total_received_usd + @total_cash_deposits).round(2)
      @budgeted_usd        = company_gigs.sum(:amount).to_f
      @upcoming_usd        = current_company.gigs.where("date >= ?", Date.today).sum(:amount).to_f

      # 2. Nómina Pagada a Trabajadores (Músicos y Staff) - Excluye ajustes contables sintéticos y shows previos al reinicio
      payroll_scope            = current_company.employee_payments.approved.where.not(funding_source: 'external_capital').where.not(payment_method: 'Ajuste contable').joins(:gig).where("gigs.date >= ?", reset_date)
      @total_payroll_paid      = payroll_scope.sum(:amount).to_f
      @total_payroll_from_fund = @total_payroll_paid

      # 3. Gastos de Mantenimiento y Reparaciones (Taller)
      company_maintenance = MaintenanceRecord.joins(:item).where(items: { company_id: current_company.id }).where("maintenance_records.completed_at >= ? OR (maintenance_records.completed_at IS NULL AND maintenance_records.created_at >= ?)", reset_date, reset_date.beginning_of_day)
      @total_maintenance_cost = company_maintenance.sum(:cost).to_f
      @maintenance_count = company_maintenance.count

      # 4. Total Inversiones en Equipos / Activos
      company_investments = current_company.investments.where("investments.date >= ? OR (investments.date IS NULL AND investments.created_at >= ?)", reset_date, reset_date.beginning_of_day)
      @total_invested_usd = company_investments.sum(:amount).to_f
      @investments_count  = company_investments.count

      # 5. Retiros directos de caja
      @total_cash_withdrawals = current_company.cash_adjustments.where("date >= ?", reset_date).outflows.sum(:amount).to_f

      # 6. Ganancia Neta Real y Rentabilidad (Flujo Real de Caja)
      @total_expenses_usd = (@total_payroll_from_fund + @total_maintenance_cost + @total_invested_usd + @total_cash_withdrawals).round(2)
      @net_profit_usd     = (@total_inflow_usd - @total_expenses_usd).round(2)
      @profit_margin_pct  = @total_inflow_usd > 0 ? ((@net_profit_usd / @total_inflow_usd) * 100).round(1) : 0.0
      @roi_usd            = @total_invested_usd > 0 ? (((@total_inflow_usd - @total_payroll_from_fund - @total_maintenance_cost) / @total_invested_usd) * 100).round(1) : 0.0
    else
      company_gigs = current_company.gigs
      company_gig_payments = GigPayment.joins(:gig).where(gigs: { company_id: current_company.id }).approved

      # 1. Cobros en USD (Moneda única del sistema)
      @total_received_usd  = company_gig_payments.sum(:amount).to_f
      @total_cash_deposits = current_company.cash_adjustments.inflows.sum(:amount).to_f
      @total_inflow_usd    = (@total_received_usd + @total_cash_deposits).round(2)
      @budgeted_usd        = company_gigs.sum(:amount).to_f
      @upcoming_usd        = company_gigs.where("date >= ?", Date.today).sum(:amount).to_f

      # 2. Nómina Pagada a Trabajadores (Músicos y Staff) - Excluye ajustes contables
      @total_payroll_paid      = current_company.employee_payments.approved.where.not(payment_method: 'Ajuste contable').sum(:amount).to_f
      @total_payroll_from_fund = current_company.employee_payments.approved.where.not(funding_source: 'external_capital').where.not(payment_method: 'Ajuste contable').sum(:amount).to_f

      # 3. Gastos de Mantenimiento y Reparaciones (Taller)
      company_maintenance = MaintenanceRecord.joins(:item).where(items: { company_id: current_company.id })
      @total_maintenance_cost = company_maintenance.sum(:cost).to_f
      @maintenance_count = company_maintenance.count

      # 4. Total Inversiones en Equipos / Activos
      company_investments = current_company.investments
      @total_invested_usd = company_investments.sum(:amount).to_f
      @investments_count  = company_investments.count

      # 5. Retiros directos de caja
      @total_cash_withdrawals = current_company.cash_adjustments.outflows.sum(:amount).to_f

      # 6. Ganancia Neta Real y Rentabilidad (Flujo Real de Caja)
      @total_expenses_usd = (@total_payroll_from_fund + @total_maintenance_cost + @total_invested_usd + @total_cash_withdrawals).round(2)
      @net_profit_usd     = (@total_inflow_usd - @total_expenses_usd).round(2)
      @profit_margin_pct  = @total_inflow_usd > 0 ? ((@net_profit_usd / @total_inflow_usd) * 100).round(1) : 0.0
      @roi_usd            = @total_invested_usd > 0 ? (((@total_inflow_usd - @total_payroll_from_fund - @total_maintenance_cost) / @total_invested_usd) * 100).round(1) : 0.0
    end

    # 7. Historial Mensual Detallado
    months_hash = {}
    min_date = (@financial_scope == 'current_cycle' && reset_date.present?) ? reset_date.beginning_of_month : nil

    # Cobros por mes de pago
    gp_scope = company_gig_payments.where.not(date_paid: nil)
    gp_scope = gp_scope.where("date_paid >= ?", min_date) if min_date
    gp_scope.find_each do |p|
      month_date = p.date_paid.beginning_of_month
      key = month_date.strftime("%Y-%m")
      months_hash[key] ||= {
        date: month_date,
        month_label: month_date.strftime("%m/%Y"),
        month_name: month_date.strftime("%B %Y"),
        received: 0.0,
        payroll: 0.0,
        maintenance: 0.0,
        investments: 0.0,
        adjustments_in: 0.0,
        adjustments_out: 0.0,
        gigs_count: 0
      }
      months_hash[key][:received] += p.amount.to_f
    end

    # Aportes y retiros de caja por mes
    ca_scope = current_company.cash_adjustments.where.not(date: nil)
    ca_scope = ca_scope.where("date >= ?", min_date) if min_date
    ca_scope.find_each do |adj|
      month_date = adj.date.beginning_of_month
      key = month_date.strftime("%Y-%m")
      months_hash[key] ||= {
        date: month_date,
        month_label: month_date.strftime("%m/%Y"),
        month_name: month_date.strftime("%B %Y"),
        received: 0.0,
        payroll: 0.0,
        maintenance: 0.0,
        investments: 0.0,
        adjustments_in: 0.0,
        adjustments_out: 0.0,
        gigs_count: 0
      }
      if adj.inflow?
        months_hash[key][:received] += adj.amount.to_f
        months_hash[key][:adjustments_in] += adj.amount.to_f
      else
        months_hash[key][:adjustments_out] += adj.amount.to_f
      end
    end

    # Nómina pagada por mes (excluye ajustes contables sintéticos)
    ep_scope = current_company.employee_payments.approved.where.not(date_paid: nil).where.not(payment_method: 'Ajuste contable')
    if min_date
      ep_scope = ep_scope.joins(:gig).where("gigs.date >= ?", reset_date)
    end
    ep_scope.find_each do |ep|
      month_date = ep.date_paid.beginning_of_month
      key = month_date.strftime("%Y-%m")
      months_hash[key] ||= {
        date: month_date,
        month_label: month_date.strftime("%m/%Y"),
        month_name: month_date.strftime("%B %Y"),
        received: 0.0,
        payroll: 0.0,
        maintenance: 0.0,
        investments: 0.0,
        adjustments_in: 0.0,
        adjustments_out: 0.0,
        gigs_count: 0
      }
      months_hash[key][:payroll] += ep.amount.to_f
    end

    # Reparaciones por mes
    company_maintenance.find_each do |mr|
      next unless mr.cost.to_f > 0
      date = mr.completed_at || mr.created_at&.to_date || Date.today
      next if min_date && date < min_date
      month_date = date.beginning_of_month
      key = month_date.strftime("%Y-%m")
      months_hash[key] ||= {
        date: month_date,
        month_label: month_date.strftime("%m/%Y"),
        month_name: month_date.strftime("%B %Y"),
        received: 0.0,
        payroll: 0.0,
        maintenance: 0.0,
        investments: 0.0,
        adjustments_in: 0.0,
        adjustments_out: 0.0,
        gigs_count: 0
      }
      months_hash[key][:maintenance] += mr.cost.to_f
    end

    # Inversiones por mes
    company_investments.find_each do |inv|
      next unless inv.amount.to_f > 0
      date = inv.date || inv.created_at&.to_date || Date.today
      next if min_date && date < min_date
      month_date = date.beginning_of_month
      key = month_date.strftime("%Y-%m")
      months_hash[key] ||= {
        date: month_date,
        month_label: month_date.strftime("%m/%Y"),
        month_name: month_date.strftime("%B %Y"),
        received: 0.0,
        payroll: 0.0,
        maintenance: 0.0,
        investments: 0.0,
        adjustments_in: 0.0,
        adjustments_out: 0.0,
        gigs_count: 0
      }
      months_hash[key][:investments] += inv.amount.to_f
    end

    # Shows por mes
    company_gigs.where.not(date: nil).find_each do |gig|
      month_date = gig.date.beginning_of_month
      next if min_date && month_date < min_date
      key = month_date.strftime("%Y-%m")
      months_hash[key] ||= {
        date: month_date,
        month_label: month_date.strftime("%m/%Y"),
        month_name: month_date.strftime("%B %Y"),
        received: 0.0,
        payroll: 0.0,
        maintenance: 0.0,
        investments: 0.0,
        adjustments_in: 0.0,
        adjustments_out: 0.0,
        gigs_count: 0
      }
      months_hash[key][:gigs_count] += 1
    end

    @monthly_breakdown = months_hash.values.sort_by { |m| m[:date] }.reverse
    @monthly_breakdown.each do |m|
      m[:total_outflow] = (m[:payroll] + m[:maintenance] + m[:investments] + m[:adjustments_out]).round(2)
      m[:net_profit] = (m[:received] - m[:total_outflow]).round(2)
      m[:margin_pct] = m[:received] > 0 ? ((m[:net_profit] / m[:received]) * 100).round(1) : 0.0
    end

    # 8. Clientes Clave (Mayor Facturación Real)
    client_gigs_scope = (@financial_scope == 'current_cycle' && reset_date.present?) ? current_company.gigs.where("gigs.date >= ?", reset_date) : current_company.gigs
    @top_clients = current_company.clients
                         .joins(:gigs)
                         .merge(client_gigs_scope)
                         .group("clients.id")
                         .select("clients.*, SUM(gigs.amount) AS total_spent, COUNT(gigs.id) AS gigs_count")
                         .order("total_spent DESC")
                         .limit(5)

    # 9. Locaciones más frecuentes
    @top_locations = company_gigs.where.not(location: [nil, ""])
                        .group(:location)
                        .order("count_all DESC")
                        .limit(5)
                        .count
  end

  def my_payments
    unless current_user.staff? || current_user.musician? || current_user.leader? || current_user.superadmin?
      redirect_to root_path, alert: "No tienes permiso para acceder a esta sección."
      return
    end

    @worker = if (current_user.leader? || current_user.superadmin?) && params[:user_id].present?
                current_company.users.find_by(id: params[:user_id]) || current_user
              else
                current_user
              end

    @employee_payments = @worker.employee_payments.includes(:gig).order(created_at: :desc)
    @worker_payment_items = @worker.worker_payment_items
    @total_expected = @worker.total_agreed_amount
    @total_paid = @worker.total_paid_amount
    @total_owed = @worker.pending_balance
  end

  def help
  end

  def normativas
  end

  def terms
    render layout: 'landing'
  end

  def privacy
    render layout: 'landing'
  end

  def suspended
    render layout: false
  end
end