class ClientsController < ApplicationController
  before_action :require_leader!

  def index
    @clients = current_company.clients.includes(gigs: :gig_payments)

    @all_clients_list = current_company.clients.includes(gigs: :gig_payments)
    @total_debt_global = @all_clients_list.sum(&:total_debt)
    @debtors_count = @all_clients_list.count(&:has_debt?)

    if params[:query].present?
      terms = params[:query].split(/\s+/)
      terms.each do |term|
        next if term.blank?
        query_term = "%#{term}%"
        @clients = @clients.where("unaccent(name) ILIKE unaccent(?) OR phone ILIKE ?", query_term, query_term)
      end
    end

    if params[:priority].present?
      @clients = @clients.where(priority: params[:priority].downcase)
    end

    if params[:has_debt] == "true"
      @clients = @clients.to_a.select(&:has_debt?)
    end

    if params[:sort] == "deuda_desc"
      @clients = @clients.to_a.sort_by { |c| -c.total_debt }
    elsif params[:sort] == "presupuesto_desc" || params[:sort] == "presupuesto_asc"
      direction = params[:sort] == "presupuesto_desc" ? "DESC" : "ASC"
      @clients = @clients.left_joins(:gigs)
                         .group("clients.id")
                         .order(Arel.sql("COALESCE(SUM(gigs.amount), 0) #{direction}"))
    elsif params[:sort] == "antiguedad_asc"
      @clients = @clients.order(created_at: :asc)
    else
      @clients = @clients.is_a?(Array) ? @clients.sort_by { |c| -c.created_at.to_i } : @clients.order(created_at: :desc)
    end
  end

  def debts
    all_clients = current_company.clients.includes(gigs: :gig_payments)

    all_unpaid_gigs = current_company.gigs.includes(:client, :gig_payments).all.select { |g| g.remaining_amount.to_f > 0 }
    @expired_unpaid_gigs = all_unpaid_gigs.select { |g| g.date.present? && g.date < Date.today }
    @upcoming_unpaid_gigs = all_unpaid_gigs.select { |g| g.date.blank? || g.date >= Date.today }

    @total_debt_global = all_unpaid_gigs.sum { |g| g.remaining_amount.to_f }
    @expired_debt_total = @expired_unpaid_gigs.sum { |g| g.remaining_amount.to_f }
    @total_unpaid_gigs_count = all_unpaid_gigs.size
    @expired_unpaid_gigs_count = @expired_unpaid_gigs.size
    @total_debtors_count = all_clients.count(&:has_debt?)

    @clients_with_debt = all_clients.select(&:has_debt?)

    if params[:query].present?
      query_term = params[:query].downcase.strip
      @clients_with_debt = @clients_with_debt.select do |c|
        c.name.to_s.downcase.include?(query_term) ||
        c.phone.to_s.downcase.include?(query_term) ||
        c.email.to_s.downcase.include?(query_term)
      end
    end

    if params[:date_status] == "expired"
      @clients_with_debt = @clients_with_debt.select do |c|
        c.unpaid_gigs.any? { |g| g.date.present? && g.date < Date.today }
      end
    elsif params[:date_status] == "upcoming"
      @clients_with_debt = @clients_with_debt.select do |c|
        c.unpaid_gigs.any? { |g| g.date.blank? || g.date >= Date.today }
      end
    end

    @clients_with_debt = @clients_with_debt.sort_by { |c| -c.total_debt }
  end

  def new
    @client = current_company.clients.build
  end

  def show
    @client = current_company.clients.find(params[:id])
    @ultimo_gig = @client.gigs.order(date: :desc).first
    @preset_budgets = current_company.preset_budgets.order(title: :asc)
  end

  def create
    @client = current_company.clients.build(client_params)
    if @client.save
      @client.update_priority! if @client.respond_to?(:update_priority!)
      redirect_to clients_path, notice: "🎯 ¡Cliente registrado con éxito!"
    else
      @preset_budgets = current_company.preset_budgets.order(title: :asc)
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @client = current_company.clients.find(params[:id])
    if @client.update(client_params)
      @client.update_priority! if @client.respond_to?(:update_priority!)
      redirect_to client_path(@client), notice: "✅ Datos actualizados correctamente."
    else
      @ultimo_gig = @client.gigs.order(date: :desc).first
      @preset_budgets = current_company.preset_budgets.order(title: :asc)
      render :show, status: :unprocessable_entity
    end
  end

  def merge
    @target = current_company.clients.find(params[:id])
    @source = current_company.clients.find_by(id: params[:source_client_id])

    if @source.nil?
      redirect_to client_path(@target), alert: "⚠️ No se encontró el cliente a fusionar."
      return
    end

    if @source.id == @target.id
      redirect_to client_path(@target), alert: "⚠️ No puedes fusionar un cliente consigo mismo."
      return
    end

    ActiveRecord::Base.transaction do
      @source.gigs.update_all(client_id: @target.id)
      User.where(client_id: @source.id).update_all(client_id: @target.id)

      @target.update(phone: @source.phone) if @target.phone.blank? || @target.phone == "0000000000"
      @target.update(email: @source.email) if @target.email.blank? && @source.email.present?
      @target.update(notes: [@target.notes, @source.notes].compact.join(" | ")) if @source.notes.present? && @target.notes != @source.notes

      @source.destroy!
      @target.update_priority!
    end

    redirect_to client_path(@target), notice: "🔗 ¡Clientes fusionados! Todos los shows fueron transferidos."
  rescue ActiveRecord::RecordNotFound
    redirect_to clients_path, alert: "Error: uno de los clientes no existe."
  end

  private

  def client_params
    params.require(:client).permit(
      :name, :phone, :email, :notes, 
      gigs_attributes: [:id, :amount, :location, :currency, :date]
    )
  end
end