class PagesController < ApplicationController
  def dashboard
    @total_items = Item.sum(:quantity)
    @items_danados = Item.where(status: "Dañado").count
    @items_excelente = Item.where(status: "Excelente").count
    
    @proximos_gigs = Gig.where("date >= ?", Date.today).order(date: :asc).limit(5)
    @total_clients = Client.count
  end

  def availability
    # 1. Buscamos todas las fechas de gigs futuros
    future_gigs = Gig.where("date >= ?", Date.today)
    dates = future_gigs.pluck(:date).uniq.compact.sort

    @conflicts = []

    dates.each do |date|
      # 2. Agrupamos los items reservados para esta fecha
      gig_items_on_date = GigItem.joins(:gig).where(gigs: { date: date })
      
      # Sumamos cantidades por item_id
      sums = gig_items_on_date.group(:item_id).sum(:quantity)
      
      sums.each do |item_id, total_requested|
        item = Item.find(item_id)
        if total_requested > item.quantity
          # 3. Hay un conflicto! Buscamos qué gigs están involucrados
          gigs_involved = future_gigs.joins(:gig_items).where(date: date, gig_items: { item_id: item_id })
          @conflicts << {
            date: date,
            item: item,
            requested: total_requested,
            available: item.quantity,
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
  end
end