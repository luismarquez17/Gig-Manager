# frozen_string_literal: true

class ReinvestmentGoalsController < ApplicationController
  before_action :require_leader!
  before_action :set_goal, only: [:show, :edit, :update, :destroy, :deposit, :toggle_status, :quick_purchase_item]

  def index
    @current_cash_balance = current_company.current_cash_balance

    # 1. Deudas del sistema (músicos / personal por shows ya realizados)
    @worker_metrics = WorkerBalanceService.build_metrics_for_company(current_company)
    @total_pending_debts = @worker_metrics.sum { |m| m[:past_balance] }.round(2)

    @system_debts = []
    @worker_metrics.each do |m|
      next if m[:past_balance] <= 0

      worker_name = m[:worker]&.display_name || m[:worker]&.email || (current_company.venue_mode? ? "Personal" : "Trabajador")
      if m[:gig_debts].present? && m[:gig_debts].any?
        m[:gig_debts].each_with_index do |d, idx|
          concept = if d[:gig].present?
                      show_name = d[:gig].client&.name || "#{current_company.term_for(:event_singular, 'Show')} ##{d[:gig].id}"
                      show_date = d[:gig].date ? d[:gig].date.strftime("%d/%m/%Y") : "S/F"
                      "#{show_name} (#{show_date})"
                    else
                      d[:title] || "Ajuste contable pendiente"
                    end
          @system_debts << {
            id: "worker_#{m[:worker].id}_debt_#{idx}",
            worker_id: m[:worker].id,
            debtor_name: worker_name,
            concept: concept,
            amount: d[:pending_amount].to_f.round(2)
          }
        end
      else
        @system_debts << {
          id: "worker_#{m[:worker].id}_balance",
          worker_id: m[:worker].id,
          debtor_name: worker_name,
          concept: "Deuda acumulada de shows pasados",
          amount: m[:past_balance].to_f.round(2)
        }
      end
    end

    # 2. Ítems pendientes de la lista de compras para evaluar en el simulador
    @shopping_items = current_company.shopping_items.pending.order(priority: :desc, created_at: :asc)

    # 3. Datos de shows venideros y ganancia promedio para proyecciones
    recent_gigs = current_company.gigs.where("amount > 0").order(date: :desc).limit(10)
    profits = recent_gigs.map { |g| g.actual_cash_profit.to_f }.select(&:positive?)
    @avg_gig_profit = profits.any? ? (profits.sum / profits.size.to_f).round(2) : 250.0
    @upcoming_gigs_count = current_company.gigs.where("date >= ?", Date.today).count

    # 4. Compatibilidad con metas previas existentes
    @goals = current_company.reinvestment_goals.order(status: :asc, priority: :desc, created_at: :desc)
    @active_goals = @goals.select(&:active?)
    @completed_goals = @goals.select(&:completed?)
    @total_goals_target = @active_goals.sum { |g| g.effective_target_amount }.round(2)
    @total_goals_saved = @active_goals.sum { |g| g.saved_amount.to_f }.round(2)
    @total_pending_deficit = [@total_goals_target - @total_goals_saved, 0.0].max.round(2)
    @total_completed_count = @completed_goals.size

    @recommendation_service = GoalRecommendationService.new(company: current_company, custom_cash: @current_cash_balance)
    @smart_recommendations = @recommendation_service.smart_recommendations
  end

  def show
    @items = @goal.shopping_items.order(status: :asc, priority: :desc, created_at: :asc)
    @pending_items = @items.select(&:pending?)
    @purchased_items = @items.select(&:purchased?)

    @contributions = @goal.goal_savings_contributions.includes(:gig, :user).order(date: :desc, created_at: :desc).limit(20)

    @recommendation_service = GoalRecommendationService.new(company: current_company, goal: @goal)
    @smart_recommendations = @recommendation_service.smart_recommendations
    @breakdown = @recommendation_service.items_breakdown(@goal.saved_amount)
  end

  def new
    @goal = current_company.reinvestment_goals.build(currency: 'USD', priority: :medium)
  end

  def create
    @goal = current_company.reinvestment_goals.build(goal_params)
    @goal.currency = 'USD'

    if @goal.save
      # Si se pasaron ítems iniciales rápidos o se desea redirigir
      redirect_to reinvestment_goal_path(@goal), notice: "🎯 ¡Meta '#{@goal.title}' creada exitosamente! Ahora añade los ítems o equipos que deseas comprar."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @goal.update(goal_params)
      redirect_to reinvestment_goal_path(@goal), notice: "✏️ Meta '#{@goal.title}' actualizada correctamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @goal.title
    @goal.destroy
    redirect_to reinvestment_goals_path, notice: "🗑️ Meta '#{title}' eliminada."
  end

  def deposit
    amount = params[:amount].to_s.tr(',', '.').strip.to_f
    gig_id = params[:gig_id].presence
    notes = params[:notes].presence || "Aporte al fondo de ahorro"

    if amount <= 0
      redirect_back fallback_location: reinvestment_goal_path(@goal), alert: "El monto a ahorrar debe ser mayor a 0."
      return
    end

    gig = current_company.gigs.find_by(id: gig_id) if gig_id.present?

    contribution = @goal.goal_savings_contributions.build(
      amount: amount,
      currency: 'USD',
      date: Date.today,
      user: current_user,
      gig: gig,
      notes: notes
    )

    if contribution.save
      formatted = view_context.number_with_precision(amount, precision: 2)
      redirect_back fallback_location: reinvestment_goal_path(@goal), notice: "💰 ¡Se han guardado $#{formatted} USD en la meta '#{@goal.title}'! Tu progreso avanzó al #{@goal.progress_percentage}%."
    else
      redirect_back fallback_location: reinvestment_goal_path(@goal), alert: "No se pudo registrar el ahorro: #{contribution.errors.full_messages.join(', ')}"
    end
  end

  def toggle_status
    new_status = @goal.active? ? 'completed' : 'active'
    completed_at = new_status == 'completed' ? Time.current : nil
    @goal.update_columns(status: new_status, completed_at: completed_at)

    status_label = new_status == 'completed' ? 'Completada 🎉' : 'Reactivada 🔄'
    redirect_back fallback_location: reinvestment_goal_path(@goal), notice: "La meta '#{@goal.title}' ahora está #{status_label}."
  end

  def quick_purchase_item
    item = @goal.shopping_items.find(params[:item_id])
    item.update!(status: :purchased)
    @goal.check_auto_completion!

    redirect_to add_to_inventory_shopping_item_path(item), notice: "🎉 ¡Felicitaciones! Has marcado como comprado: '#{item.name}'. Ahora puedes sumarlo al inventario de la agrupación."
  end

  private

  def set_goal
    @goal = current_company.reinvestment_goals.find(params[:id])
  end

  def goal_params
    params.require(:reinvestment_goal).permit(
      :title, :objective, :purpose, :target_amount, :priority, :status,
      :target_date, :image, :image_base64
    )
  end
end
