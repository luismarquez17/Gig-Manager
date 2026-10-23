class ClientsController < ApplicationController
  before_action :require_leader!
  before_action -> { require_module!(:clients_crm) }

  def index
    @clients = current_company.clients.includes(gigs: :gig_payments)

    # Calculamos las métricas globales de deuda directamente en SQL sin cargar
    # todos los clientes en RAM. Antes se cargaban TODOS los clientes DOS VECES.
    @total_debt_global = GigPayment.joins(:gig)
                                   .where(gigs: { company_id: current_company.id })
                                   .sum(:amount)
                                   .then { |total_paid|
                                     current_company.gigs.sum(:amount).to_f - total_paid.to_f
                                   }
    @total_debt_global = [@total_debt_global, 0.0].max

    # Cuenta clientes con al menos un gig sin pagar completamente
    @debtors_count = current_company.clients
                                    .joins(gigs: :gig_payments)
                                    .where('gigs.amount > COALESCE((SELECT SUM(gp.amount) FROM gig_payments gp WHERE gp.gig_id = gigs.id), 0)')
                                    .distinct
                                    .count

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

    # Filtramos gigs con saldo pendiente directamente en SQL, sin cargar todos en RAM.
    # Antes: .all.select { |g| g.remaining_amount.to_f > 0 } cargaba TODO en memoria.
    unpaid_gigs_scope = current_company.gigs
                                       .includes(:client, :gig_payments)
                                       .where(
                                         'gigs.amount > COALESCE((SELECT SUM(gp.amount) FROM gig_payments gp WHERE gp.gig_id = gigs.id), 0)'
                                       )

    all_unpaid_gigs = unpaid_gigs_scope.to_a
    @expired_unpaid_gigs  = all_unpaid_gigs.select { |g| g.date.present? && g.date < Date.today }
    @upcoming_unpaid_gigs = all_unpaid_gigs.reject { |g| g.date.present? && g.date < Date.today }

    @total_debt_global       = all_unpaid_gigs.sum { |g| g.remaining_amount.to_f }
    @expired_debt_total      = @expired_unpaid_gigs.sum { |g| g.remaining_amount.to_f }
    @total_unpaid_gigs_count = all_unpaid_gigs.size
    @expired_unpaid_gigs_count = @expired_unpaid_gigs.size
    @total_debtors_count     = all_clients.count(&:has_debt?)

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
  end

  def debt
    @client = current_company.clients.find(params[:id])
    @unpaid_gigs = @client.sorted_unpaid_gigs
    @total_debt = @client.total_debt
    @all_gigs = @client.gigs.includes(:gig_payments).order(date: :desc, id: :desc)
    @recent_payments = GigPayment.joins(:gig)
                                 .where(gigs: { client_id: @client.id, company_id: current_company.id })
                                 .approved
                                 .order(date_paid: :desc, created_at: :desc)
                                 .limit(10)
    @rate_info = (current_company&.exchange_rate_details rescue nil) || (ExchangeRateService.today_rate_info rescue nil)
  end

  def record_debt_payment
    @client = current_company.clients.find(params[:id])
    amount = params[:amount].to_s.tr(',', '.').strip.to_f
    payment_method = params[:payment_method].presence || 'cash'
    date_paid = params[:date_paid].present? ? (Date.parse(params[:date_paid]) rescue Date.today) : Date.today
    reference_number = params[:reference_number].presence
    notes = params[:notes].presence
    receipt_image = params[:receipt_image]

    result = @client.apply_debt_payment!(
      amount: amount,
      payment_method: payment_method,
      date_paid: date_paid,
      reference_number: reference_number,
      notes: notes,
      receipt_image: receipt_image,
      user: current_user
    )

    notice_parts = ["✅ ¡Abono de $#{sprintf('%.2f', result[:total_applied])} USD registrado con éxito en la cuenta de #{@client.name}!"]

    if result[:settled_gigs].any?
      settled_names = result[:settled_gigs].map { |g| g.location.presence || g.date&.strftime('%d/%m/%Y') || "##{g.id}" }
      notice_parts << "🎯 Shows 100% saldados (#{result[:settled_gigs].size}): #{settled_names.join(', ')}."
    end

    if result[:partial_gigs].any?
      p_gig = result[:partial_gigs].first
      p_name = p_gig.location.presence || p_gig.date&.strftime('%d/%m/%Y') || "##{p_gig.id}"
      notice_parts << "⏳ Show con saldo parcial: #{p_name} (restante: $#{sprintf('%.2f', p_gig.remaining_amount)} USD)."
    end

    destination = case params[:redirect_to]
                  when 'debts' then debts_clients_path
                  when 'client' then client_path(@client)
                  else debt_client_path(@client)
                  end

    redirect_to destination, notice: notice_parts.join(" ")
  rescue ArgumentError => e
    destination = params[:redirect_to] == 'debts' ? debts_clients_path : (debt_client_path(@client) rescue clients_path)
    redirect_to destination, alert: "⚠️ No se pudo procesar el abono: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "[ClientsController#record_debt_payment] Error: #{e.message}\n#{e.backtrace[0..5].join("\n")}"
    destination = params[:redirect_to] == 'debts' ? debts_clients_path : (debt_client_path(@client) rescue clients_path)
    redirect_to destination, alert: "⚠️ Ocurrió un error inesperado al procesar el abono: #{e.message}"
  end

  def create
    @client = current_company.clients.build(client_params)
    if @client.save
      @client.update_priority! if @client.respond_to?(:update_priority!)
      redirect_to clients_path, notice: "🎯 ¡Cliente registrado con éxito!"
    else
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
      render :show, status: :unprocessable_entity
    end
  end

  private

  def client_params
    params.require(:client).permit(
      :name, :phone, :email, :notes, 
      gigs_attributes: [:id, :amount, :location, :currency, :date]
    )
  end
end