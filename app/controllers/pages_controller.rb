class PagesController < ApplicationController
  before_action :require_leader!, only: [:availability, :financials]

  def dashboard
    if current_user.leader? || current_user.superadmin?
      @total_items = InventoryItem.joins(:item).where(items: { company_id: current_company.id }).count
      @items_danados = InventoryItem.joins(:item).where(items: { company_id: current_company.id }, status: 'damaged').count
      @items_excelente = InventoryItem.joins(:item).where(items: { company_id: current_company.id }, status: 'available').count

      @total_gigs = current_company.gigs.count
      @upcoming_gigs_count = current_company.gigs.where("date >= ?", Date.today).count
      @proximos_gigs = current_company.gigs.where("date >= ?", Date.today).order(date: :asc).limit(5)
      @total_clients = current_company.clients.count

      @total_received = GigPayment.joins(:gig).where(gigs: { company_id: current_company.id }).sum(:amount).to_f
      @total_payroll_reserved = FundAllocation.joins(:gig).where(gigs: { company_id: current_company.id }, fund_type: 'payroll').sum(:amount).to_f
      @total_payroll_spent = FundAllocation.joins(:gig, :fund_expenses).where(gigs: { company_id: current_company.id }, fund_type: 'payroll').sum('fund_expenses.amount').to_f
      @total_payroll_available = @total_payroll_reserved - @total_payroll_spent
      @total_funds_allocated = FundAllocation.joins(:gig).where(gigs: { company_id: current_company.id }).sum(:amount).to_f
      @total_pending_worker_payments = current_company.users.workers.to_a.sum(&:pending_balance)
      @needed_payroll = [@total_pending_worker_payments - @total_payroll_available, 0].max
      @shows_with_payroll = current_company.gigs.joins(:fund_allocations).where(fund_allocations: { fund_type: 'payroll' }).distinct.count
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
      @proximos_gigs = current_user.client ? current_user.client.gigs.where("date >= ?", Date.today).order(date: :asc).limit(5) : []
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
    company_gigs = current_company.gigs
    company_gig_payments = GigPayment.joins(:gig).where(gigs: { company_id: current_company.id })

    # 1. Dinero REALMENTE COBRADO por moneda
    @total_received_usd = company_gig_payments.where(currency: 'USD').sum(:amount).to_f
    @total_received_bs = company_gig_payments.where(currency: 'BS').sum(:amount).to_f

    # Presupuesto acordado por moneda
    @budgeted_usd = company_gigs.where(currency: 'USD').sum(:amount).to_f
    @budgeted_bs = company_gigs.where(currency: 'BS').sum(:amount).to_f

    # Proyecciones (gigs futuros)
    @upcoming_usd = company_gigs.where("date >= ?", Date.today).where(currency: 'USD').sum(:amount).to_f
    @upcoming_bs = company_gigs.where("date >= ?", Date.today).where(currency: 'BS').sum(:amount).to_f

    # 2. Gastos de mantenimiento
    company_maintenance = MaintenanceRecord.joins(:item).where(items: { company_id: current_company.id })
    @total_maintenance_cost = company_maintenance.sum(:cost)
    @maintenance_by_status = company_maintenance.group(:status).sum(:cost)

    # 3. Top Clientes
    @top_clients = current_company.clients.joins(:gigs)
                         .group("clients.id")
                         .select("clients.name, SUM(gigs.amount) as total_spent, COUNT(gigs.id) as gigs_count")
                         .order("total_spent DESC")
                         .limit(5)

    # 4. Locaciones más frecuentes
    @top_locations = company_gigs.where.not(location: [nil, ""])
                        .group(:location)
                        .order("count_all DESC")
                        .limit(5)
                        .count

    # 5. Ingresos mensuales históricos
    payments_by_month_usd = company_gig_payments.where(currency: 'USD').group("TO_CHAR(date_paid, 'MM/YYYY')").sum(:amount)
    payments_by_month_bs = company_gig_payments.where(currency: 'BS').group("TO_CHAR(date_paid, 'MM/YYYY')").sum(:amount)
    @monthly_revenue = {}
    (payments_by_month_usd.keys | payments_by_month_bs.keys).each do |month|
      @monthly_revenue[month] = {
        usd: payments_by_month_usd[month].to_f,
        bs: payments_by_month_bs[month].to_f
      }
    end
    @monthly_revenue = @monthly_revenue.sort_by { |k, _| Date.strptime(k, "%m/%Y") rescue Date.today }.to_h

    # 6. Total inversiones del grupo
    @total_invested_usd = current_company.investments.where(currency: 'USD').sum(:amount).to_f
    @total_invested_bs = current_company.investments.where(currency: 'BS').sum(:amount).to_f

    # 7. Pagos registrados para shows
    @total_gig_payments = company_gig_payments.count
    @paid_shows_count = company_gigs.joins(:gig_payments).distinct.count

    received_by_gig = company_gig_payments.group(:gig_id).sum(:amount)
    @gig_payment_status_counts = { paid: 0, partial: 0, unpaid: 0 }
    @total_unpaid_amount_by_currency = Hash.new(0.0)

    company_gigs.includes(:client).find_each do |gig|
      received = received_by_gig[gig.id].to_f
      remaining = gig.amount.to_f - received
      currency = gig.currency.presence || 'USD'

      if received.zero?
        @gig_payment_status_counts[:unpaid] += 1
      elsif remaining.positive?
        @gig_payment_status_counts[:partial] += 1
      else
        @gig_payment_status_counts[:paid] += 1
      end

      @total_unpaid_amount_by_currency[currency] += remaining.positive? ? remaining : 0.0
    end

    @top_unpaid_gigs = company_gigs.left_joins(:gig_payments)
                          .select('gigs.*, COALESCE(SUM(gig_payments.amount), 0) AS total_received')
                          .group('gigs.id')
                          .order(Arel.sql('gigs.amount - COALESCE(SUM(gig_payments.amount), 0) DESC'))
                          .limit(5)

    # 8. Pagos a empleados
    @total_employee_payments = current_company.employee_payments.sum(:amount).to_f

    # 9. Tasa de reinversión configurada
    @reinvest_rate = FinanceSetting.instance.reinvest_rate.to_f

    # 10. Fondos y capital acumulado
    company_fund_allocations = FundAllocation.joins(:gig).where(gigs: { company_id: current_company.id })
    @total_funds_by_type = company_fund_allocations.group(:fund_type).sum(:amount)
    @funds_by_type_and_currency = company_fund_allocations.group(:fund_type, :currency).sum(:amount)
    @capital_total = company_fund_allocations.where(fund_type: 'capital').sum(:amount).to_f
    @repairs_fund = company_fund_allocations.where(fund_type: 'repairs').sum(:amount).to_f
    @savings_fund = company_fund_allocations.where(fund_type: 'savings').sum(:amount).to_f
    @total_funds = company_fund_allocations.sum(:amount).to_f

    # 11. Gastos por tipo de fondo
    @spent_by_type = company_fund_allocations.joins(:fund_expenses).group('fund_allocations.fund_type').sum('fund_expenses.amount')

    total_received = company_gig_payments.sum(:amount)
    total_paid_employees = current_company.employee_payments.sum(:amount)
    total_allocated = company_fund_allocations.sum(:amount)
    @unallocated_surplus = total_received - total_paid_employees - total_allocated

    # ROI / Ganancia Neta por moneda
    @net_gain_usd = @total_received_usd - @total_invested_usd
    @roi_usd      = @total_invested_usd > 0 ? (@net_gain_usd / @total_invested_usd) * 100 : 0

    @net_gain_bs  = @total_received_bs - @total_invested_bs
    @roi_bs       = @total_invested_bs > 0 ? (@net_gain_bs / @total_invested_bs) * 100 : 0
  end

  def my_payments
    unless current_user.staff? || current_user.musician?
      redirect_to root_path, alert: "No tienes permiso para acceder a esta sección."
      return
    end

    @employee_payments = current_user.employee_payments.includes(:gig).order(created_at: :desc)
    @worker_payment_items = current_user.worker_payment_items
    @total_expected = current_user.total_agreed_amount
    @total_paid = current_user.total_paid_amount
    @total_owed = current_user.pending_balance
  end

  def help
  end

  def normativas
  end

  def suspended
    render layout: false
  end
end