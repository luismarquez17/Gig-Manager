# frozen_string_literal: true

class GigsController < ApplicationController
  include Gigs::StaffManagement
  include Gigs::CloseoutActions
  include Gigs::FinancialActions
  include Gigs::ViewFormats

  before_action :require_leader!, except: [:show, :load_in_checklist, :my, :flashcard, :stage_mode]
  before_action -> { require_module!(:gigs) }
  before_action -> { require_module!(:inventory) }, only: [:load_in_checklist, :add_kit]
  before_action :require_staff_or_leader!, only: [:show, :load_in_checklist, :print_contract, :flashcard, :stage_mode]
  before_action :check_gig_assignment, only: [:show, :load_in_checklist, :flashcard, :stage_mode]
  before_action :set_gig, only: [
    :add_kit, :assign_staff, :remove_staff, :update_staff_pay,
    :print_contract, :flashcard, :stage_mode, :add_upsell,
    :adjust_price, :edit, :update, :destroy, :closeout,
    :process_closeout, :save_profit_to_goal
  ]

  def check_gig_assignment
    @gig = current_company.gigs.find_by!(id: params[:id])
    # Usamos exists? para verificar la asignación directamente en SQL sin cargar
    # todos los gigs asignados en memoria.
    unless current_user.superadmin? || current_user.leader? ||
           current_user.staff_assignments.exists?(gig_id: @gig.id)
      redirect_to root_path, alert: "No tienes asignado este evento."
    end
  end

  def index
    # 1. Unimos la tabla de clientes para poder buscar y filtrar dentro de la empresa
    @gigs = current_company.gigs.left_joins(:client).includes(:client, :gig_payments, :staff_assignments)

    # 2. Buscador inteligente por nombre de cliente, teléfono, correo, ubicación o detalles del toque
    if params[:query].present?
      terms = params[:query].split(/\s+/)
      terms.each do |term|
        next if term.blank?
        query_term = "%#{term}%"
        @gigs = @gigs.where(
          "unaccent(clients.name) ILIKE unaccent(?) OR " \
          "clients.phone ILIKE ? OR " \
          "unaccent(gigs.location) ILIKE unaccent(?) OR " \
          "unaccent(gigs.details) ILIKE unaccent(?) OR " \
          "unaccent(COALESCE(gigs.music_notes, '')) ILIKE unaccent(?) OR " \
          "gigs.client_email ILIKE ?",
          query_term, query_term, query_term, query_term, query_term, query_term
        )
      end
    end

    # 3. Filtro por prioridad
    if params[:priority].present?
      @gigs = @gigs.where(clients: { priority: params[:priority].downcase })
    end

    # Siguiente show absoluto de la empresa (calculado con fecha >= hoy)
    # Lo cargamos con cliente para el mensaje/banner superior
    @next_gig = current_company.gigs.includes(:client).where("gigs.date >= ?", Date.current).order(date: :asc, start_time: :asc).first

    # Filtro por Fecha (El Siguiente vs Próximos vs Pasados)
    if params[:date_filter] == "next"
      next_id = @gigs.where("gigs.date >= ?", Date.current).order(date: :asc, start_time: :asc).limit(1).pluck(:id).first
      @gigs = next_id ? @gigs.where(id: next_id) : @gigs.none
    elsif params[:date_filter] == "upcoming"
      @gigs = @gigs.where("gigs.date >= ?", Date.current)
    elsif params[:date_filter] == "past"
      @gigs = @gigs.where("gigs.date < ?", Date.current)
    end

    # 4. Lógica de Ordenamiento Dinámico
    case params[:sort]
    when "monto_desc"
      @gigs = @gigs.order(amount: :desc)
    when "monto_asc"
      @gigs = @gigs.order(amount: :asc)
    when "fecha_asc"
      @gigs = @gigs.order(date: :asc)
    when "fecha_desc"
      @gigs = @gigs.order(date: :desc)
    else
      # Si el filtro es "Próximos" o "El Siguiente", ordenamos del show más cercano (Date.current ➔ Futuro)
      if params[:date_filter].in?(["upcoming", "next"])
        @gigs = @gigs.order(date: :asc, start_time: :asc)
      else
        # Orden por defecto general: Fecha más reciente primero
        @gigs = @gigs.order(date: :desc)
      end
    end
    
    # 5. Cálculos para el resumen (basados en la lista ya filtrada)
    # Mostramos dinero REALMENTE COBRADO (gig_payments), no el presupuesto acordado
    gig_ids = @gigs.pluck(:id)
    @total_usd = GigPayment.where(gig_id: gig_ids).sum(:amount).to_f
  end

  def show
    @gig = current_company.gigs.includes(:client, :gig_payments, :gig_timeline_items, :gig_upsell_requests, :employee_payments, staff_assignments: :user).find(params[:id])
    @gig_items = @gig.gig_items.includes(:item).order('items.name ASC')
    @new_gig_item = GigItem.new

    if current_user.leader? || current_user.superadmin?
      @active_goals = current_company.reinvestment_goals.active.order(priority: :desc, created_at: :desc)
      @primary_goal = @active_goals.first
      if @primary_goal.present?
        @goal_recommendation_service = GoalRecommendationService.new(company: current_company, gig: @gig, goal: @primary_goal)
        @goal_recommendations = @goal_recommendation_service.smart_recommendations
        @goal_breakdown = @goal_recommendation_service.items_breakdown(@gig.net_free_money_unallocated)
      end
    end
  end

  # Show gigs assigned to current staff member
  def my
    @gigs = current_user.assigned_gigs.order(date: :asc)

    gig_ids = @gigs.pluck(:id)
    @pending_gig_items = GigItem.where(gig_id: gig_ids).where(loaded_quantity: 0)
    @items_to_load_count = @pending_gig_items.sum(:quantity)
  end

  def new
    @gig = Gig.new
    @available_quotes = current_company.client_quotes.convertible.recent_first

    if params[:quote_id].present?
      @quote = current_company.client_quotes.find_by(id: params[:quote_id])
      if @quote.present?
        quote_name = @quote.client_name.to_s.strip
        client = @quote.client

        # Si el cliente asignado no coincide con el nombre especificado en el formulario
        if quote_name.present? && (client.nil? || client.name.to_s.strip.downcase != quote_name.downcase)
          client = Client.find_or_create_for_gig(
            company: current_company,
            email: @quote.client_email,
            name: quote_name,
            phone: @quote.client_phone
          )
          @quote.update_column(:client_id, client.id) if client.present?
        end

        @gig.client = client
        @gig.client_id = client&.id
        @gig.client_email = @quote.client_email.presence || client&.email
        @gig.amount = @quote.amount
        @gig.currency = @quote.currency
        @gig.location = @quote.event_location
        @gig.date = @quote.event_date || Date.today
        @gig.start_time = @quote.start_time
        @gig.end_time = @quote.end_time
        @gig.details = @quote.details
        @selected_quote_id = @quote.id
        @default_advance_amount = @quote.advance_amount
      end
    end
  end

  def create
    @gig = current_company.gigs.build(gig_params)

    name_to_use = params[:client_name].presence || params.dig(:gig, :client_name).presence
    email_to_use = @gig.client_email.presence || params[:client_email].presence
    phone_to_use = params[:client_phone].presence

    if name_to_use.present?
      current_client = current_company.clients.find_by(id: @gig.client_id)
      # Si no hay cliente o el cliente seleccionado no coincide con el nombre ingresado
      if current_client.nil? || current_client.name.to_s.strip.downcase != name_to_use.to_s.strip.downcase
        matched_client = Client.find_or_create_for_gig(
          company: current_company,
          email: email_to_use,
          name: name_to_use,
          phone: phone_to_use
        )
        @gig.client = matched_client if matched_client.present?
        @gig.client_id = matched_client&.id
      end
    elsif @gig.client_id.blank? && email_to_use.present?
      matched_client = Client.find_or_create_for_gig(
        company: current_company,
        email: email_to_use,
        name: nil,
        phone: phone_to_use
      )
      @gig.client = matched_client if matched_client.present?
      @gig.client_id = matched_client&.id
    end

    if @gig.save
      @gig.client&.update_priority!

      advance_val = params[:advance_amount].to_s.tr(',', '.').to_f
      if advance_val > 0
        @gig.gig_payments.create!(
          amount: advance_val,
          currency: @gig.currency.presence || "USD",
          date_paid: params[:advance_date_paid].presence || Date.today,
          is_advance: true,
          payer_name: @gig.client&.name.presence || params[:client_name].presence || "Cliente",
          notes: "Adelanto Inicial (Anticipo) registrado al crear el evento."
        ) rescue nil
      end

      if params[:client_quote_id].present?
        quote = current_company.client_quotes.find_by(id: params[:client_quote_id])
        if quote
          quote.update(status: 'converted', gig_id: @gig.id, client_id: @gig.client_id)
        end
      end

      redirect_to gigs_path, notice: "Toque registrado con éxito."
    else
      @available_quotes = current_company.client_quotes.convertible.recent_first
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @gig.update(gig_params)
      @gig.client&.update_priority! if @gig.client
      respond_to do |format|
        format.html { redirect_to gig_path(@gig), notice: "Evento actualizado correctamente." }
        format.json { render json: { success: true, music_notes: @gig.music_notes } }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { success: false, errors: @gig.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @client = @gig.client
    
    if @gig.destroy
      @client.update_priority! if @client
      redirect_to gigs_path, notice: "Registro eliminado y prioridad actualizada."
    else
      redirect_to gigs_path, alert: "No se pudo eliminar el registro."
    end
  end

  private

  def set_gig
    @gig = current_company.gigs.find(params[:id])
  end

  def gig_params
    params.require(:gig).permit(
      :client_id, :client_email, :amount, :date, :location,
      :currency, :details, :music_notes, :start_time, :end_time
    ).tap do |whitelisted|
      if params[:gig].has_key?(:custom_upsells)
        whitelisted[:custom_upsells] = params[:gig][:custom_upsells].presence&.to_unsafe_h || {}
      end
    end
  end
end