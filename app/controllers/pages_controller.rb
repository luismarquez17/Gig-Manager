class PagesController < ApplicationController
  before_action :require_leader!, only: [:availability, :financials]

  def dashboard
    if current_user.leader?
      @total_items = InventoryItem.count
      @items_danados = InventoryItem.damaged.count
      @items_excelente = InventoryItem.available.count

      @proximos_gigs = Gig.where("date >= ?", Date.today).order(date: :asc).limit(5)
      @total_clients = Client.count

      @total_received = GigPayment.sum(:amount).to_f
      @total_payroll_reserved = FundAllocation.where(fund_type: 'payroll').sum(:amount).to_f
      @total_payroll_spent = FundAllocation.joins(:fund_expenses).where(fund_type: 'payroll').sum('fund_expenses.amount').to_f
      @total_payroll_available = @total_payroll_reserved - @total_payroll_spent
      @total_funds_allocated = FundAllocation.sum(:amount).to_f
      @total_pending_worker_payments = EmployeePayment.where('expected_amount > amount').sum('expected_amount - amount').to_f
      @needed_payroll = [@total_pending_worker_payments - @total_payroll_available, 0].max
      @shows_with_payroll = Gig.joins(:fund_allocations).where(fund_allocations: { fund_type: 'payroll' }).distinct.count
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
    else
      # Client
      @proximos_gigs = current_user.client ? current_user.client.gigs.where("date >= ?", Date.today).order(date: :asc).limit(5) : []
    end
  end

  def availability
    # Buscamos gigs desde hace 7 días hacia el futuro para capturar shows recientes
    # y detectar conflictos de equipos aún relevantes
    window_start = Date.today - 7.days
    relevant_gigs = Gig.where("date >= ?", window_start)
    dates = relevant_gigs.pluck(:date).uniq.compact.sort

    @conflicts = []

    dates.each do |date|
      # 2. Agrupamos los items reservados para esta fecha
      gig_items_on_date = GigItem.joins(:gig).where(gigs: { date: date })
      
      # Sumamos cantidades por item_id
      sums = gig_items_on_date.group(:item_id).sum(:quantity)
      
      sums.each do |item_id, total_requested|
        item = Item.find(item_id)
        if total_requested > item.available_count
          # 3. Hay un conflicto! Buscamos qué gigs están involucrados
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
    # 1. Dinero REALMENTE COBRADO por moneda (basado en pagos registrados)
    @total_received_usd = GigPayment.where(currency: 'USD').sum(:amount).to_f
    @total_received_bs = GigPayment.where(currency: 'BS').sum(:amount).to_f

    # Presupuesto acordado por moneda (para contexto)
    @budgeted_usd = Gig.where(currency: 'USD').sum(:amount).to_f
    @budgeted_bs = Gig.where(currency: 'BS').sum(:amount).to_f

    # Proyecciones (gigs futuros) - basadas en presupuesto acordado
    @upcoming_usd = Gig.where("date >= ?", Date.today).where(currency: 'USD').sum(:amount).to_f
    @upcoming_bs = Gig.where("date >= ?", Date.today).where(currency: 'BS').sum(:amount).to_f

    # 2. Gastos de mantenimiento
    @total_maintenance_cost = MaintenanceRecord.sum(:cost)
    @maintenance_by_status = MaintenanceRecord.group(:status).sum(:cost)

    # 3. Top Clientes (con base en el total gastado en shows)
    @top_clients = Client.joins(:gigs)
                         .group("clients.id")
                         .select("clients.name, SUM(gigs.amount) as total_spent, COUNT(gigs.id) as gigs_count")
                         .order("total_spent DESC")
                         .limit(5)

    # 4. Locaciones más frecuentes
    @top_locations = Gig.where.not(location: [nil, ""])
                        .group(:location)
                        .order("count_all DESC")
                        .limit(5)
                        .count

    # 5. Ingresos mensuales históricos (dinero realmente cobrado)
    payments_by_month_usd = GigPayment.where(currency: 'USD').group("TO_CHAR(date_paid, 'MM/YYYY')").sum(:amount)
    payments_by_month_bs = GigPayment.where(currency: 'BS').group("TO_CHAR(date_paid, 'MM/YYYY')").sum(:amount)
    @monthly_revenue = {}
    (payments_by_month_usd.keys | payments_by_month_bs.keys).each do |month|
      @monthly_revenue[month] = {
        usd: payments_by_month_usd[month].to_f,
        bs: payments_by_month_bs[month].to_f
      }
    end
    # Ordenamos los meses cronológicamente
    @monthly_revenue = @monthly_revenue.sort_by { |k, _| Date.strptime(k, "%m/%Y") rescue Date.today }.to_h

    # 3. Total inversiones del grupo
    @total_invested_usd = Investment.where(currency: 'USD').sum(:amount).to_f
    @total_invested_bs = Investment.where(currency: 'BS').sum(:amount).to_f

    # 7. Pagos registrados para shows (métricas)
    @total_gig_payments = GigPayment.count
    @paid_shows_count = Gig.joins(:gig_payments).distinct.count

    received_by_gig = GigPayment.group(:gig_id).sum(:amount)
    @gig_payment_status_counts = { paid: 0, partial: 0, unpaid: 0 }
    @total_unpaid_amount_by_currency = Hash.new(0.0)

    Gig.includes(:client).find_each do |gig|
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

    @top_unpaid_gigs = Gig.left_joins(:gig_payments)
                          .select('gigs.*, COALESCE(SUM(gig_payments.amount), 0) AS total_received')
                          .group('gigs.id')
                          .order(Arel.sql('gigs.amount - COALESCE(SUM(gig_payments.amount), 0) DESC'))
                          .limit(5)

    # 8. Pagos a empleados
    @total_employee_payments = EmployeePayment.sum(:amount).to_f

    # 9. Tasa de reinversión configurada
    @reinvest_rate = FinanceSetting.first&.reinvest_rate.to_f

    # 10. Fondos y capital acumulado
    @total_funds_by_type = FundAllocation.group(:fund_type).sum(:amount)
    @funds_by_type_and_currency = FundAllocation.group(:fund_type, :currency).sum(:amount)
    @capital_total = FundAllocation.where(fund_type: 'capital').sum(:amount).to_f
    @repairs_fund = FundAllocation.where(fund_type: 'repairs').sum(:amount).to_f
    @savings_fund = FundAllocation.where(fund_type: 'savings').sum(:amount).to_f
    @total_funds = FundAllocation.sum(:amount).to_f

    # 11. Gastos por tipo de fondo (sumamos fund_expenses por fund_type)
    @spent_by_type = FundAllocation.joins(:fund_expenses).group('fund_allocations.fund_type').sum('fund_expenses.amount')

    # Dinero sin asignar: ingresos totales reales - pagos empleados - asignaciones
    total_received = GigPayment.sum(:amount)
    total_paid_employees = EmployeePayment.sum(:amount)
    total_allocated = FundAllocation.sum(:amount)
    @unallocated_surplus = total_received - total_paid_employees - total_allocated

    # ROI / Ganancia Neta por moneda (cobrado real vs invertido)
    @net_gain_usd = @total_received_usd - @total_invested_usd
    @roi_usd      = @total_invested_usd > 0 ? (@net_gain_usd / @total_invested_usd) * 100 : 0

    @net_gain_bs  = @total_received_bs - @total_invested_bs
    @roi_bs       = @total_invested_bs > 0 ? (@net_gain_bs / @total_invested_bs) * 100 : 0
  end

  def help
    # A simple help page for quick guidance to users
  end
end