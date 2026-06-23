class PagesController < ApplicationController
  before_action :require_leader!, only: [:availability, :financials]

  def dashboard
    if current_user.leader?
      @total_items = InventoryItem.count
      @items_danados = InventoryItem.damaged.count
      @items_excelente = InventoryItem.available.count
      
      @proximos_gigs = Gig.where("date >= ?", Date.today).order(date: :asc).limit(5)
      @total_clients = Client.count
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
      @proximos_gigs = []
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
    # 1. Totales de ingresos por moneda
    @total_usd = Gig.where(currency: 'USD').sum(:amount)
    @total_bs = Gig.where(currency: 'BS').sum(:amount)
    
    # Proyecciones (gigs futuros)
    @upcoming_usd = Gig.where("date >= ?", Date.today).where(currency: 'USD').sum(:amount)
    @upcoming_bs = Gig.where("date >= ?", Date.today).where(currency: 'BS').sum(:amount)

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

    # 5. Ingresos mensuales históricos
    gigs_by_month = Gig.all.group_by { |g| g.date&.strftime("%m/%Y") }
    @monthly_revenue = {}
    gigs_by_month.each do |month, gigs|
      next if month.nil?
      usd_sum = gigs.select { |g| g.currency == 'USD' }.sum(&:amount)
      bs_sum = gigs.select { |g| g.currency == 'BS' }.sum(&:amount)
      @monthly_revenue[month] = { usd: usd_sum, bs: bs_sum }
    end
    # Ordenamos los meses cronológicamente
    @monthly_revenue = @monthly_revenue.sort_by { |k, _| Date.strptime(k, "%m/%Y") rescue Date.today }.to_h

    # 6. Total inversiones del grupo
    @total_invested_usd = Investment.where(currency: 'USD').sum(:amount)

    # 7. Pagos registrados para shows (métricas)
    @total_gig_payments = GigPayment.sum(:amount)
    @paid_shows_count = Gig.joins(:gig_payments).distinct.count

    # 8. Pagos a empleados
    @total_employee_payments = EmployeePayment.sum(:amount)

    # 9. Tasa de reinversión configurada
    @reinvest_rate = FinanceSetting.first&.reinvest_rate || 0.0

    # 10. Fondos y capital acumulado
    @total_funds_by_type = FundAllocation.group(:fund_type).sum(:amount)
    @capital_total = FundAllocation.where(fund_type: 'capital').sum(:amount)
    @repairs_fund = FundAllocation.where(fund_type: 'repairs').sum(:amount)
    @savings_fund = FundAllocation.where(fund_type: 'savings').sum(:amount)
    @total_funds = FundAllocation.sum(:amount)

    # 11. Gastos por tipo de fondo (sumamos fund_expenses por fund_type)
    @spent_by_type = FundAllocation.joins(:fund_expenses).group('fund_allocations.fund_type').sum('fund_expenses.amount')

    # Dinero sin asignar: ingresos totales - pagos empleados - asignaciones
    total_received = Gig.sum(:amount)
    total_paid_employees = EmployeePayment.sum(:amount)
    total_allocated = FundAllocation.sum(:amount)
    @unallocated_surplus = total_received - total_paid_employees - total_allocated
  end

  def help
    # A simple help page for quick guidance to users
  end
end