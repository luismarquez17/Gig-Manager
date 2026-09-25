class ClientQuotesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:public_show, :public_submit, :access, :setup_password]
  skip_before_action :verify_authenticity_token, only: [:public_submit]
  before_action :set_quote, only: [:show, :destroy]
  before_action :set_public_quote, only: [:public_show, :public_submit, :access, :setup_password]
  layout 'portal', only: [:public_show, :public_submit, :access]

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
      begin
        @quote.notify_leaders_of_acceptance!
      rescue Exception => notif_err
        Rails.logger.error("Error al notificar líderes tras envío de cotización: #{notif_err.message}")
      end

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
  rescue Exception => e
    Rails.logger.error("Error en ClientQuotesController#public_submit: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    render json: { success: false, error: "Ocurrió un error al procesar el presupuesto: #{e.message}" }, status: :unprocessable_entity
  end

  def access
    @company = @quote.company
    @client = @quote.client

    # 1. Si el usuario ya está autenticado en este navegador con la cuenta del cliente
    if user_signed_in?
      if current_user.email.to_s.downcase == @quote.client_email.to_s.downcase || (current_user.client_id.present? && current_user.client_id == @quote.client_id)
        redirect_to root_path, notice: "🎉 ¡Hola #{current_user.display_name}! Has accedido a tu portal de cliente."
        return
      else
        redirect_to root_path, alert: "Ya tienes una sesión iniciada con la cuenta #{current_user.email}."
        return
      end
    end

    # 2. Si no está autenticado, asegurar que el registro de cliente exista
    if @client.nil? && (@quote.client_name.present? || @quote.client_phone.present? || @quote.client_email.present?)
      @client = Client.find_or_create_for_gig(
        company: @quote.company,
        name: @quote.client_name,
        phone: @quote.client_phone,
        email: @quote.client_email
      )
      @quote.update_column(:client_id, @client.id) if @client.present? && @quote.client_id != @client.id
    end
  end

  def setup_password
    @company = @quote.company
    @client = @quote.client

    email = params[:email].to_s.strip.downcase
    phone = params[:phone].to_s.strip
    password = params[:password].to_s
    password_confirmation = params[:password_confirmation].to_s

    quote_email = @quote.client_email.to_s.strip.downcase
    quote_phone = @quote.client_phone.to_s.strip

    phone_clean = phone.gsub(/\D/, '')
    quote_phone_clean = quote_phone.gsub(/\D/, '')

    email_matches = quote_email.present? && email == quote_email
    phone_matches = quote_phone_clean.present? && phone_clean.present? && (phone_clean == quote_phone_clean || phone_clean.end_with?(quote_phone_clean.last(7)))

    unless email_matches || phone_matches
      redirect_to access_public_client_quote_path(@quote.public_token), alert: "❌ El correo o teléfono ingresado no coincide con los datos registrados en este presupuesto."
      return
    end

    if password.length < 6
      redirect_to access_public_client_quote_path(@quote.public_token), alert: "❌ La contraseña debe tener al menos 6 caracteres."
      return
    end

    if password != password_confirmation
      redirect_to access_public_client_quote_path(@quote.public_token), alert: "❌ Las contraseñas no coinciden."
      return
    end

    @client ||= Client.find_or_create_for_gig(
      company: @quote.company,
      name: @quote.client_name,
      phone: @quote.client_phone,
      email: @quote.client_email
    )
    @quote.update_column(:client_id, @client.id) if @client.present? && @quote.client_id != @client.id

    user = User.find_or_create_client_user(
      company: @quote.company,
      client: @client,
      email: quote_email.presence || email,
      name: @quote.client_name
    )

    if user.present?
      user.password = password
      user.password_confirmation = password_confirmation
      if user.save
        sign_in(user)
        redirect_to root_path, notice: "🔒 ¡Tu cuenta ha sido protegida y activada con éxito! Bienvenido a tu portal, #{user.display_name}."
      else
        redirect_to access_public_client_quote_path(@quote.public_token), alert: "No se pudo guardar la contraseña: #{user.errors.full_messages.join(', ')}"
      end
    else
      redirect_to access_public_client_quote_path(@quote.public_token), alert: "Ocurrió un error al configurar tu cuenta. Por favor contacta a la agrupación."
    end
  rescue StandardError => e
    Rails.logger.error("Error en ClientQuotesController#setup_password: #{e.class}: #{e.message}")
    redirect_to access_public_client_quote_path(@quote.public_token), alert: "Ocurrió un error: #{e.message}"
  end

  private

  def set_quote
    @client_quote = current_company.client_quotes.find(params[:id])
  end

  def set_public_quote
    @quote = ClientQuote.find_by(public_token: params[:token])
    if @quote.nil?
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
    else
      ActsAsTenant.current_tenant = @quote.company
      Current.company = @quote.company
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
