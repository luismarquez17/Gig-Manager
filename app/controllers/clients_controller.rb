class ClientsController < ApplicationController
  before_action :require_leader!

  def index
    # Iniciamos con todos los clientes (cargamos de manera anticipada los gigs para evitar N+1 en average_budget)
    @clients = Client.includes(:gigs).all

    # 1. Buscador Inteligente por nombre o teléfono (insensible a acentos/tildes y tokenizado)
    if params[:query].present?
      terms = params[:query].split(/\s+/)
      terms.each do |term|
        next if term.blank?
        query_term = "%#{term}%"
        @clients = @clients.where("unaccent(name) ILIKE unaccent(?) OR phone ILIKE ?", query_term, query_term)
      end
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

  def merge
    @target = Client.find(params[:id])
    @source = Client.find_by(id: params[:source_client_id])

    if @source.nil?
      redirect_to client_path(@target), alert: "⚠️ No se encontró el cliente a fusionar."
      return
    end

    if @source.id == @target.id
      redirect_to client_path(@target), alert: "⚠️ No puedes fusionar un cliente consigo mismo."
      return
    end

    ActiveRecord::Base.transaction do
      # 1. Transferir todos los gigs del source al target
      @source.gigs.update_all(client_id: @target.id)

      # 2. Transferir la vinculación de usuarios (si algún User apuntaba al source)
      User.where(client_id: @source.id).update_all(client_id: @target.id)

      # 3. Preservar info útil del source si el target no la tiene
      @target.update(phone: @source.phone) if @target.phone.blank? || @target.phone == "0000000000"
      @target.update(email: @source.email) if @target.email.blank? && @source.email.present?
      @target.update(notes: [@target.notes, @source.notes].compact.join(" | ")) if @source.notes.present? && @target.notes != @source.notes

      # 4. Eliminar el cliente duplicado
      @source.destroy!

      # 5. Recalcular prioridad del target con los gigs combinados
      @target.update_priority!
    end

    redirect_to client_path(@target), notice: "🔗 ¡Clientes fusionados! Todos los shows fueron transferidos."
  rescue ActiveRecord::RecordNotFound
    redirect_to clients_path, alert: "Error: uno de los clientes no existe."
  end

  private

  def client_params
    # Agregamos los campos que usas en el form
    params.require(:client).permit(
      :name, :phone, :email, :notes, 
      gigs_attributes: [:id, :amount, :location, :currency, :date]
    )
  end
end