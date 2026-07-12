class GigsController < ApplicationController
  before_action :require_leader!, except: [:show, :load_in_checklist, :my]
  before_action :require_staff_or_leader!, only: [:show, :load_in_checklist, :print_contract]
  before_action :check_gig_assignment, only: [:show, :load_in_checklist]

  def check_gig_assignment
    @gig = Gig.find(params[:id])
    unless current_user.leader? || current_user.assigned_gigs.include?(@gig)
      redirect_to root_path, alert: "No tienes asignado este evento."
    end
  end

  def index
    # 1. Unimos la tabla de clientes para poder buscar y filtrar
    @gigs = Gig.left_joins(:client).includes(:client).all

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
          "gigs.client_email ILIKE ?",
          query_term, query_term, query_term, query_term, query_term
        )
      end
    end

    # 3. Filtro por prioridad
    if params[:priority].present?
      @gigs = @gigs.where(clients: { priority: params[:priority].downcase })
    end

    # 4. Lógica de Ordenamiento Dinámico
    case params[:sort]
    when "monto_desc"
      @gigs = @gigs.order(amount: :desc)
    when "monto_asc"
      @gigs = @gigs.order(amount: :asc)
    else
      # Orden por defecto: Fecha (más reciente primero)
      @gigs = @gigs.order(date: :desc)
    end
    
    # 5. Cálculos para el resumen (basados en la lista ya filtrada)
    # Mostramos dinero REALMENTE COBRADO (gig_payments), no el presupuesto acordado
    gig_ids = @gigs.pluck(:id)
    @total_usd = GigPayment.where(gig_id: gig_ids, currency: 'USD').sum(:amount).to_f
    @total_bs = GigPayment.where(gig_id: gig_ids, currency: 'BS').sum(:amount).to_f
  end

  def show
    @gig ||= Gig.find(params[:id])
    @gig_items = @gig.gig_items.includes(:item).order('items.name ASC')
    @new_gig_item = GigItem.new
  end

  def load_in_checklist
    @gig ||= Gig.find(params[:id])
    @gig_items = @gig.gig_items.includes(:item).order('items.name ASC')
    # Use a layout specifically without navbar, or render false and build full html
    render layout: false
  end

  def add_kit
    @gig = Gig.find(params[:id])
    kit = Kit.find(params[:kit_id])

    if kit.kit_items.empty?
      redirect_to gig_path(@gig), alert: "La plantilla seleccionada está vacía."
      return
    end

    ActiveRecord::Base.transaction do
      kit.kit_items.each do |kit_item|
        gig_item = @gig.gig_items.find_or_initialize_by(item_id: kit_item.item_id)
        gig_item.quantity ||= 0
        gig_item.quantity += kit_item.quantity
        gig_item.save!
      end
    end

    redirect_to gig_path(@gig), notice: "Plantilla '#{kit.name}' aplicada con éxito al evento."
  rescue ActiveRecord::RecordNotFound
    redirect_to gig_path(@gig), alert: "Plantilla no encontrada."
  end

  def assign_staff
    @gig = Gig.find(params[:id])
    user = User.find_by(id: params[:staff_id])

    if user && (user.staff? || user.leader?)
      if @gig.staff_members.include?(user)
        redirect_to gig_path(@gig), alert: "Este trabajador ya está asignado."
      else
        @gig.staff_members << user
        redirect_to gig_path(@gig), notice: "Trabajador asignado con éxito."
      end
    else
      redirect_to gig_path(@gig), alert: "Usuario no válido."
    end
  end

  # Show gigs assigned to current staff member
  def my
    @gigs = current_user.assigned_gigs.order(date: :asc)

    gig_ids = @gigs.pluck(:id)
    @pending_gig_items = GigItem.where(gig_id: gig_ids).where(loaded_quantity: 0)
    @items_to_load_count = @pending_gig_items.sum(:quantity)
  end

  def print_contract
    @gig = Gig.find(params[:id])
    render layout: false
  end

  def new
    @gig = Gig.new
  end

  def create
    @gig = Gig.new(gig_params)
    if @gig.save
      @gig.client.update_priority! 
      redirect_to gigs_path, notice: "Toque registrado y prioridad actualizada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @gig = Gig.find(params[:id])
  end

  def update
    @gig = Gig.find(params[:id])
    if @gig.update(gig_params)
      @gig.client.update_priority! if @gig.client
      redirect_to gig_path(@gig), notice: "Evento actualizado correctamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @gig = Gig.find(params[:id])
    @client = @gig.client
    
    if @gig.destroy
      # Recalculamos la prioridad para que si el show borrado era grande, 
      # el cliente cambie de color (ej: de verde a amarillo)
      @client.update_priority!
      redirect_to gigs_path, notice: "Registro eliminado y prioridad actualizada."
    else
      redirect_to gigs_path, alert: "No se pudo eliminar el registro."
    end
  end

  private

  def gig_params
    params.require(:gig).permit(:client_id, :client_email, :amount, :date, :location, :currency, :details, :start_time, :end_time)
  end
end