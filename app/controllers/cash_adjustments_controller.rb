class CashAdjustmentsController < ApplicationController
  before_action :require_leader!
  before_action :set_cash_adjustment, only: [:edit, :update, :destroy]

  def index
    @adjustments = current_company.cash_adjustments.recent_first

    # 1. Componentes de Entrada (Inflows)
    @total_gigs_received   = GigPayment.joins(:gig).where(gigs: { company_id: current_company.id }).sum(:amount).to_f
    @total_cash_deposits   = current_company.cash_adjustments.inflows.sum(:amount).to_f
    @total_inflow          = (@total_gigs_received + @total_cash_deposits).round(2)

    # 2. Componentes de Salida (Outflows)
    @total_payroll_paid    = current_company.employee_payments.approved.sum(:amount).to_f
    @total_maintenance     = MaintenanceRecord.joins(:item).where(items: { company_id: current_company.id }).sum(:cost).to_f
    @total_investments     = current_company.investments.sum(:amount).to_f
    @total_cash_withdrawals = current_company.cash_adjustments.outflows.sum(:amount).to_f
    @total_outflow         = (@total_payroll_paid + @total_maintenance + @total_investments + @total_cash_withdrawals).round(2)

    # 3. Saldo Neto Actual en Caja
    @current_cash_balance  = (@total_inflow - @total_outflow).round(2)

    # 4. Libro Diario Unificado de Movimientos de Dinero
    transactions = []

    # Cobros de shows
    GigPayment.joins(:gig).includes(gig: :client).where(gigs: { company_id: current_company.id }).where.not(date_paid: nil).find_each do |p|
      client_name = p.gig.client&.name || p.gig.client_email || "Show"
      show_date = p.gig.date ? "(Evento: #{p.gig.date.strftime('%d/%m/%Y')})" : ""
      desc = "Cobro de Show - #{client_name} #{show_date}"
      desc += " [#{p.notes}]" if p.notes.present?

      transactions << {
        date: p.date_paid,
        created_at: p.created_at,
        category: :gig_payment,
        category_label: "Cobro de Show",
        emoji: "🎸",
        badge_bg: "#dcfce7",
        badge_color: "#166534",
        description: desc,
        amount: p.amount.to_f,
        direction: :inflow,
        url: gig_path(p.gig),
        raw_id: p.id
      }
    end

    # Pagos de nómina aprobados
    current_company.employee_payments.approved.includes(:user, :gig).where.not(date_paid: nil).find_each do |ep|
      worker_name = ep.user&.display_name || ep.user&.email || "Trabajador"
      show_info = ep.gig.present? ? " (Show #{ep.gig.client&.name || ep.gig.id})" : " (Pago general)"
      desc = "Pago de Nómina - #{worker_name}#{show_info}"
      desc += " [#{ep.notes}]" if ep.notes.present?

      transactions << {
        date: ep.date_paid,
        created_at: ep.created_at,
        category: :payroll,
        category_label: "Nómina de Personal",
        emoji: "👥",
        badge_bg: "#dbeafe",
        badge_color: "#1e40af",
        description: desc,
        amount: ep.amount.to_f,
        direction: :outflow,
        url: employee_payments_path(user_id: ep.user_id),
        raw_id: ep.id
      }
    end

    # Gastos de taller / mantenimiento
    MaintenanceRecord.joins(:item).includes(:item).where(items: { company_id: current_company.id }).where("cost > 0").find_each do |mr|
      date = mr.completed_at || mr.created_at.to_date
      item_name = mr.item&.name || "Equipo"
      desc = "Reparación Taller - #{item_name}: #{mr.description.truncate(50)}"

      transactions << {
        date: date,
        created_at: mr.created_at,
        category: :maintenance,
        category_label: "Taller / Mantenimiento",
        emoji: "🔧",
        badge_bg: "#ffe4e6",
        badge_color: "#9f1239",
        description: desc,
        amount: mr.cost.to_f,
        direction: :outflow,
        url: maintenance_records_path,
        raw_id: mr.id
      }
    end

    # Inversiones en equipos
    current_company.investments.where("amount > 0").find_each do |inv|
      date = inv.date || inv.created_at.to_date
      desc = "Compra de Equipo - #{inv.description}"
      desc += " [#{inv.notes}]" if inv.notes.present?

      transactions << {
        date: date,
        created_at: inv.created_at,
        category: :investment,
        category_label: "Inversión en Equipos",
        emoji: "📦",
        badge_bg: "#ede9fe",
        badge_color: "#5b21b6",
        description: desc,
        amount: inv.amount.to_f,
        direction: :outflow,
        url: investments_path,
        raw_id: inv.id
      }
    end

    # Ajustes directos de caja
    @adjustments.each do |adj|
      transactions << {
        date: adj.date,
        created_at: adj.created_at,
        category: :adjustment,
        category_label: adj.type_label,
        emoji: adj.type_emoji,
        badge_bg: adj.type_badge_bg,
        badge_color: adj.type_badge_color,
        description: adj.description,
        amount: adj.amount.to_f,
        direction: adj.inflow? ? :inflow : :outflow,
        url: edit_cash_adjustment_path(adj),
        raw_id: adj.id,
        is_adjustment: true,
        adjustment_record: adj
      }
    end

    # Ordenar libro diario de forma descendente por fecha
    @transactions = transactions.sort_by { |t| [t[:date] || Date.today, t[:created_at] || Time.current] }.reverse

    # Filtrado opcional
    if params[:filter] == "inflows"
      @transactions = @transactions.select { |t| t[:direction] == :inflow }
    elsif params[:filter] == "outflows"
      @transactions = @transactions.select { |t| t[:direction] == :outflow }
    elsif params[:filter] == "adjustments"
      @transactions = @transactions.select { |t| t[:is_adjustment] }
    end
  end

  def new
    @cash_adjustment = current_company.cash_adjustments.build(
      date: Date.today,
      currency: "USD",
      adjustment_type: params[:adjustment_type] || :deposit
    )
  end

  def create
    @cash_adjustment = current_company.cash_adjustments.build(cash_adjustment_params)
    @cash_adjustment.user = current_user

    if @cash_adjustment.save
      redirect_to cash_adjustments_path, notice: "Movimiento de caja registrado exitosamente: #{@cash_adjustment.type_label} ($#{@cash_adjustment.amount} #{@cash_adjustment.currency})."
    else
      flash.now[:alert] = "Error al registrar el movimiento: #{@cash_adjustment.errors.full_messages.join(', ')}"
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @cash_adjustment.update(cash_adjustment_params)
      redirect_to cash_adjustments_path, notice: "Movimiento de caja actualizado exitosamente."
    else
      flash.now[:alert] = "Error al actualizar: #{@cash_adjustment.errors.full_messages.join(', ')}"
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @cash_adjustment.destroy
    redirect_to cash_adjustments_path, notice: "Movimiento de caja eliminado exitosamente."
  end

  private

  def set_cash_adjustment
    @cash_adjustment = current_company.cash_adjustments.find(params[:id])
  end

  def cash_adjustment_params
    params.require(:cash_adjustment).permit(:amount, :currency, :adjustment_type, :date, :description)
  end
end
