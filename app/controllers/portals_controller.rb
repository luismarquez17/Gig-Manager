class PortalsController < ApplicationController
  skip_before_action :authenticate_user!
  layout 'portal'

  before_action :set_gig

  def show
    @client = @gig.client
    @gig_payments = @gig.gig_payments.order(date_paid: :desc)
    @timeline_items = @gig.gig_timeline_items.for_client.order(:position, :time)
    @staff_members = @gig.staff_members.with_attached_avatar
  end

  def worker_profile
    @worker = User.find(params[:worker_id])
    unless @gig.staff_members.include?(@worker)
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
      return
    end
  end

  def sign_contract
    if params[:signature_name].blank?
      render json: { success: false, error: "El nombre es obligatorio para firmar." }, status: :unprocessable_entity
      return
    end

    if @gig.update(
      contract_signed: true,
      contract_signed_at: Time.current,
      contract_signed_ip: request.remote_ip,
      contract_signed_name: params[:signature_name]
    )
      AppNotification.create(
        company: @gig.company,
        target_area: 'leaders',
        notification_type: 'gig_alert',
        title: "✍️ Contrato Firmado Digitalmente",
        message: "El cliente '#{@gig.contract_signed_name}' ha firmado el contrato del evento para el #{@gig.date ? @gig.date.strftime('%d/%m/%Y') : 'show'}.",
        action_url: "/gigs/#{@gig.id}"
      ) rescue nil

      render json: { 
        success: true, 
        signed_at: @gig.contract_signed_at.strftime("%d/%m/%Y %I:%M %p"),
        ip: @gig.contract_signed_ip,
        name: @gig.contract_signed_name
      }
    else
      render json: { success: false, error: "No se pudo registrar la firma." }, status: :unprocessable_entity
    end
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
      # Notificar al líder por email (en background para no retrasar la respuesta)
      UpsellMailer.new_upsell_request(req).deliver_later rescue nil

      AppNotification.create(
        company: @gig.company,
        target_area: 'leaders',
        notification_type: 'gig_alert',
        title: "🚀 Nueva Solicitud de Adicional (Upsell)",
        message: "El cliente '#{@gig.client&.name || @gig.contract_signed_name || 'Invitado'}' ha solicitado #{req.emoji} '#{req.title}' ($#{req.price} #{req.currency}).",
        action_url: "/gigs/#{@gig.id}"
      ) rescue nil

      render json: {
        success: true,
        message: "¡Solicitud enviada con éxito! El equipo organizador fue notificado y confirmará la disponibilidad a la brevedad.",
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

  def set_gig
    @gig = Gig.find_by(portal_token: params[:token])
    if @gig.nil?
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
    end
  end
end
