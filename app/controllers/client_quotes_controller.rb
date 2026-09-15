class ClientQuotesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:public_show, :public_submit]
  before_action :authenticate_user!, except: [:public_show, :public_submit]
  before_action :set_quote, only: [:show, :destroy]
  before_action :set_public_quote, only: [:public_show, :public_submit]
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

    if @quote.update(update_data)
      @quote.notify_leaders_of_acceptance!

      date_formatted = @quote.event_date ? @quote.event_date.strftime('%d/%m/%Y') : 'tu evento'
      render json: {
        success: true,
        message: "¡Muchas gracias #{@quote.display_client_name}! Tu propuesta y requerimientos para #{date_formatted} han sido recibidos con éxito. El equipo de #{@quote.company.name} ha sido notificado."
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
    if params[:client_quote].present?
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
  end

  def public_quote_params
    params.permit(
      :client_name, :client_email, :client_phone,
      :event_type, :event_date, :event_location,
      :start_time, :end_time, :amount, :currency,
      :advance_amount, :details, :preset_budget_id, :package_name
    )
  end
end
