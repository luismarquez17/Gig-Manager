class ClientsController < ApplicationController
  def index
    # Iniciamos con todos los clientes
    @clients = Client.all

    # 1. Buscador por nombre o teléfono
    if params[:query].present?
      query_term = "%#{params[:query]}%"
      @clients = @clients.where("name ILIKE ? OR phone LIKE ?", query_term, query_term)
    end

    # 2. Filtro por prioridad
    if params[:priority].present?
      @clients = @clients.where(priority: params[:priority].downcase)
    end

    # 3. Ordenamiento Dinámico (Corregido para PostgreSQL)
    case params[:sort]
    when "presupuesto_desc", "presupuesto_asc"
      direction = params[:sort] == "presupuesto_desc" ? "DESC" : "ASC"
      # Hacemos un JOIN con Gigs para sumar los montos y ordenar
      @clients = @clients.left_joins(:gigs)
                         .group("clients.id")
                         .order(Arel.sql("COALESCE(SUM(gigs.amount), 0) #{direction}"))
    when "antiguedad_asc"
      @clients = @clients.order(created_at: :asc)
    else
      @clients = @clients.order(created_at: :desc)
    end
  end

  def new
    @client = Client.new
  end

  def show
    @client = Client.find(params[:id])
    @ultimo_gig = @client.gigs.order(date: :desc).first
    @preset_budgets = PresetBudget.all.order(title: :asc)
  end

  def create
    @client = Client.new(client_params)
    if @client.save
      # No es necesario llamar update_priority! aquí si ya lo haces en el modelo
      # Pero lo dejamos por seguridad si no tienes callbacks
      @client.update_priority! if @client.respond_to?(:update_priority!)
      redirect_to clients_path, notice: "🎯 ¡Cliente registrado con éxito!"
    else
      @preset_budgets = PresetBudget.all.order(title: :asc)
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @client = Client.find(params[:id])
    if @client.update(client_params)
      @client.update_priority! if @client.respond_to?(:update_priority!)
      redirect_to client_path(@client), notice: "✅ Datos actualizados correctamente."
    else
      @ultimo_gig = @client.gigs.order(date: :desc).first
      @preset_budgets = PresetBudget.all.order(title: :asc)
      render :show, status: :unprocessable_entity
    end
  end

  private

  def client_params
    # Agregamos los campos que usas en el form
    params.require(:client).permit(
      :name, :phone, :notes, 
      gigs_attributes: [:id, :amount, :location, :currency, :date]
    )
  end
end