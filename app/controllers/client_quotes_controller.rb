class ClientQuotesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:public_show, :public_submit]
  before_action :authenticate_user!, except: [:public_show, :public_submit]
  before_action :set_quote, only: [:show, :destroy]
  before_action :set_public_quote, only: [:public_show, :public_submit]
  layout 'portal', only: [:public_show, :public_submit]

  def index
    @client_quotes = current_company.client_quotes.recent_first
  end

  def show
  end

  def new
    @client_quote = current_company.client_quotes.build(
      amount: 0.0,
      currency: current_company.currency.presence || "USD"
    )
  end

  def create
    @client_quote = current_company.client_quotes.build(quote_params)

    if @client_quote.save
      redirect_to client_quotes_path, notice: "Presupuesto creado con éxito. Puedes enviar el enlace público al cliente."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @client_quote.destroy
    redirect_to client_quotes_path, notice: "Presupuesto eliminado."
  end

  # --- VISTAS PÚBLICAS PARA EL CLIENTE ---

  def public_show
  end

  def public_submit
    if @quote.status == 'converted'
      render json: { success: false, error: "Este presupuesto ya ha sido procesado y convertido en un evento activo." }, status: :unprocessable_entity
      return
    end

    if @quote.update(public_quote_params.merge(status: 'accepted'))
      @quote.notify_leaders_of_acceptance!

      render json: {
        success: true,
        message: "¡Gracias #{@quote.client_name}! Tu información y presupuesto para el #{@quote.event_date ? @quote.event_date.strftime('%d/%m/%Y') : 'evento'} han sido recibidos y confirmados con éxito. El equipo organizador ha sido notificado."
      }
    else
      render json: { success: false, error: @quote.errors.full_messages.join(", ") }, status: :unprocessable_entity
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
    params.require(:client_quote).permit(
      :client_name, :client_email, :client_phone,
      :event_type, :event_date, :event_location,
      :start_time, :end_time, :amount, :currency,
      :advance_amount, :details
    )
  end

  def public_quote_params
    params.permit(
      :client_name, :client_email, :client_phone,
      :event_type, :event_date, :event_location,
      :start_time, :end_time, :amount, :currency,
      :advance_amount, :details
    )
  end
end
