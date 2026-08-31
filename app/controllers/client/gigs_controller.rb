class Client::GigsController < ApplicationController
  before_action :require_client!
  before_action :set_gig, only: [:show, :request_upsell]

  def index
    if current_user.client_id.present?
      @gigs = Gig.where(client_id: current_user.client_id).order(date: :desc)
    else
      @gigs = Gig.none
    end
  end

  def show
    @gig_payments = @gig.gig_payments.order(date_paid: :desc)
    @timeline_items = @gig.gig_timeline_items.for_client.order(:position, :time)
    @staff_members = @gig.staff_members.with_attached_avatar
  end

  def request_upsell
    upsell_key = params[:upsell_key].to_s
    if upsell_key.blank?
      render json: { success: false, error: "Parámetros incompletos." }, status: :unprocessable_entity
      return
    end

    available = @gig.available_upsells.find { |u| u[:key].to_s == upsell_key }

    title = params[:title].presence || available&.dig(:title) || upsell_key.humanize
    emoji = params[:emoji].presence || available&.dig(:emoji) || '🚀'
    price = (params[:price].presence || available&.dig(:price) || 0.0).to_f
    currency = params[:currency].presence || available&.dig(:currency) || @gig.currency || 'USD'
    notes = params[:notes].presence

    existing = @gig.gig_upsell_requests.where(upsell_key: upsell_key, status: 'pending').first
    if existing
      render json: {
        success: true,
        message: "Esta solicitud ya se encuentra en espera de confirmación.",
        request: { id: existing.id, status: existing.status, title: existing.title, price: existing.price }
      }
      return
    end

    req = @gig.gig_upsell_requests.create(
      upsell_key: upsell_key,
      title: title,
      emoji: emoji,
      price: price,
      currency: currency,
      notes: notes,
      status: 'pending',
      requested_at: Time.current
    )

    if req.persisted?
      # Notificar al líder por email
      UpsellMailer.new_upsell_request(req).deliver_later rescue nil

      render json: {
        success: true,
        message: "¡Solicitud enviada con éxito! El equipo organizador confirmará la disponibilidad.",
        request: {
          id: req.id,
          key: req.upsell_key,
          title: req.title,
          emoji: req.emoji,
          price: req.price,
          currency: req.currency,
          status: req.status
        }
      }
    else
      render json: { success: false, error: req.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  private

  def require_client!
    unless current_user&.client?
      redirect_to root_path, alert: "No tienes permiso para acceder a esta sección."
    end
  end

  def set_gig
    @gig = Gig.find_by(id: params[:id])
    if @gig.nil? || @gig.client_id != current_user.client_id
      redirect_to client_gigs_path, alert: "No tienes acceso a este evento."
    end
  end
end
