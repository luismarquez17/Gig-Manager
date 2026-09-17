class ClientQuotesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:public_show, :public_submit, :access]
  skip_before_action :verify_authenticity_token, only: [:public_submit]
  before_action :authenticate_user!, except: [:public_show, :public_submit, :access]
  before_action :set_quote, only: [:show, :destroy]
  before_action :set_public_quote, only: [:public_show, :public_submit, :access]
  layout 'portal', only: [:public_show, :public_submit]

  def index
    @client_quotes = current_company.client_quotes.recent_first
    @preset_budgets = current_company.preset_budgets.order(created_at: :desc)
  end

  def show
  end

  def new
    @preset_budgets = current_company.preset_budgets.order(created_at: :desc)
    preset = @preset_budgets.find_by(id: params[:preset_budget_id]) if params[:preset_budget_id].present?

    @client_quote = current_company.client_quotes.build(
      preset_budget: preset,
      package_name: preset&.title,
      amount: preset ? preset.price : 0.0,
      currency: preset ? preset.currency : (current_company.currency.presence || "USD"),
      details: preset&.description
    )
  end

  def create
    @client_quote = current_company.client_quotes.build(quote_params)
    @client_quote.currency ||= current_company.currency.presence || "USD"
    @client_quote.amount ||= 0.0

    if @client_quote.save
      redirect_to client_quotes_path, notice: "🎯 ¡Enlace generado con éxito! Ya puedes copiarlo o enviarlo por WhatsApp."
    else
      @client_quotes = current_company.client_quotes.recent_first
      @preset_budgets = current_company.preset_budgets.order(created_at: :desc)
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @client_quote.destroy
    redirect_to client_quotes_path, notice: "Presupuesto eliminado."
  end

  # --- VISTAS PÚBLICAS PARA EL CLIENTE ---

  def public_show
    @company = @quote.company
    @preset_budgets = @company.preset_budgets.order(created_at: :asc)
  end

  def public_submit
    if @quote.status == 'converted'
      render json: { success: false, error: "Este presupuesto ya ha sido procesado y convertido en un evento activo." }, status: :unprocessable_entity
      return
    end

    preset = @quote.company.preset_budgets.find_by(id: params[:preset_budget_id]) if params[:preset_budget_id].present?
    
    update_data = public_quote_params.merge(status: 'accepted')
    if preset.present?
      update_data[:preset_budget_id] = preset.id
      update_data[:package_name] ||= preset.title
    end

    # Registrar o vincular automáticamente al cliente en la base de datos
    if update_data[:client_name].present? || update_data[:client_phone].present?
      client = Client.find_or_create_for_gig(
        company: @quote.company,
        name: update_data[:client_name],
        phone: update_data[:client_phone],
        email: update_data[:client_email]
      )
      update_data[:client_id] = client.id if client.present?
    end

    if @quote.update(update_data)
      @quote.notify_leaders_of_acceptance!

      date_formatted = @quote.event_date ? @quote.event_date.strftime('%d/%m/%Y') : 'tu evento'
      access_url = access_public_client_quote_path(@quote.public_token)
      render json: {
        success: true,
        message: "¡Muchas gracias #{@quote.display_client_name}! Tu propuesta y requerimientos para #{date_formatted} han sido recibidos con éxito. El equipo de #{@quote.company.name} ha sido notificado.",
        access_url: access_url
      }
    else
      render json: { success: false, error: @quote.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error("Error en ClientQuotesController#public_submit: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    render json: { success: false, error: "Ocurrió un error al procesar el presupuesto: #{e.message}" }, status: :unprocessable_entity
  end

  def access
    begin
      client = @quote.client
      if client.nil?
        client = Client.find_or_create_for_gig(
          company: @quote.company,
          name: @quote.client_name,
          phone: @quote.client_phone,
          email: @quote.client_email
        )
        @quote.update_column(:client_id, client.id) if client.present?
      end

      # Buscar usuario existente vinculado a este cliente o a su email
      user = nil
      if client.present?
        user = User.where(company_id: @quote.company_id, client_id: client.id).first
        user ||= User.where(company_id: @quote.company_id, email: client.email).first if client.email.present?
      end

      # Si aún no tiene cuenta de usuario, crearla de inmediato sin fricción
      if user.nil? && client.present?
        user_email = client.email.presence || @quote.client_email.presence || "cliente_#{client.id}@#{@quote.company.slug.presence || 'app'}.com"
        user_name = client.name.presence || @quote.client_name.presence || "Cliente"

        user = User.find_by(email: user_email)
        if user.nil?
          random_pass = SecureRandom.hex(14)
          user = User.new(
            name: user_name,
            email: user_email,
            company: @quote.company,
            client: client,
            role: :client,
            password: random_pass,
            password_confirmation: random_pass
          )
          user.save!
        else
          user.update_column(:client_id, client.id) if user.client_id != client.id
        end
      end

      if user.present?
        sign_in(user)
        redirect_to root_path, notice: "🎉 ¡Hola #{user.display_name}! Has accedido exitosamente a tu portal de cliente."
      else
        redirect_to root_path, alert: "No se pudo iniciar sesión automáticamente. Por favor contacta a la agrupación."
      end
    rescue StandardError => e
      Rails.logger.error("Error en ClientQuotesController#access: #{e.class}: #{e.message}")
      redirect_to root_path, alert: "Ocurrió un error al ingresar al portal: #{e.message}"
    end
  end

  private

  def set_quote
    @client_quote = current_company.client_quotes.find(params[:id])
  end

  def set_public_quote
    @quote = ClientQuote.find_by(public_token: params[:token])
    if @quote.nil?
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
    end
  end

  def quote_params
    raw = if params[:client_quote].present?
      params.require(:client_quote).permit(
        :client_name, :client_email, :client_phone,
        :event_type, :event_date, :event_location,
        :start_time, :end_time, :amount, :currency,
        :advance_amount, :details, :preset_budget_id, :package_name
      )
    else
      params.permit(
        :client_name, :client_email, :client_phone,
        :event_type, :event_date, :event_location,
        :start_time, :end_time, :amount, :currency,
        :advance_amount, :details, :preset_budget_id, :package_name
      )
    end
    sanitize_quote_data(raw)
  end

  def public_quote_params
    raw = params.permit(
      :client_name, :client_email, :client_phone,
      :event_type, :event_date, :event_location,
      :start_time, :end_time, :amount, :currency,
      :advance_amount, :details, :preset_budget_id, :package_name
    )
    sanitize_quote_data(raw)
  end

  def sanitize_quote_data(raw)
    sanitized = raw.respond_to?(:to_h) ? raw.to_h.with_indifferent_access : raw.dup

    if sanitized[:amount].present? && sanitized[:amount].is_a?(String)
      sanitized[:amount] = sanitized[:amount].tr(',', '.').gsub(/[^\d.]/, '')
    end
    if sanitized[:advance_amount].present? && sanitized[:advance_amount].is_a?(String)
      sanitized[:advance_amount] = sanitized[:advance_amount].tr(',', '.').gsub(/[^\d.]/, '')
    end

    sanitized[:start_time] = nil if sanitized[:start_time].blank?
    sanitized[:end_time] = nil if sanitized[:end_time].blank?
    sanitized[:event_date] = nil if sanitized[:event_date].blank?

    sanitized
  end
end
