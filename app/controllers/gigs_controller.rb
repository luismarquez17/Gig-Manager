class GigsController < ApplicationController
  def index
    # 1. Unimos la tabla de clientes para poder buscar y filtrar
    @gigs = Gig.includes(:client).all

    # 2. Buscador por nombre o teléfono
    if params[:query].present?
      query_term = "%#{params[:query]}%"
      @gigs = @gigs.where("clients.name ILIKE ? OR clients.phone ILIKE ?", query_term, query_term)
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
    @total_usd = @gigs.where(currency: 'USD').sum(:amount)
    @total_bs = @gigs.where(currency: 'BS').sum(:amount)
  end

  def show
    @gig = Gig.find(params[:id])
    @gig_items = @gig.gig_items.includes(:item).order('items.name ASC')
    @new_gig_item = GigItem.new
  end

  def load_in_checklist
    @gig = Gig.find(params[:id])
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
    params.require(:gig).permit(:client_id, :amount, :date, :location, :currency, :details)
  end
end