class Client::GigsController < ApplicationController
  before_action :require_client!
  before_action :set_gig, only: [:show, :request_upsell, :report_payment]

  def index
    if current_user.client_id.present?
      @gigs = Gig.where(client_id: current_user.client_id).order(date: :desc)
    else
      @gigs = Gig.none
    end
  end

  def show
    @gig_payments = current_company.module_enabled?(:finances) ? @gig.gig_payments.order(date_paid: :desc) : []
    @timeline_items = current_company.module_enabled?(:gigs) ? @gig.gig_timeline_items.for_client.order(:position, :time) : []
    @staff_members = current_company.module_enabled?(:payroll) ? @gig.staff_members.with_attached_avatar : []
  end

  def request_upsell
    unless current_company.module_enabled?(:clients_crm)
      render json: { success: false, error: "El catálogo de adicionales no está disponible." }, status: :unprocessable_entity
      return
    end

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

  def report_payment
    amount = params[:amount].to_s.tr(',', '.').to_f
    if amount <= 0
      redirect_to client_gig_path(@gig), alert: "El monto del pago debe ser mayor a 0."
      return
    end

    payment = @gig.gig_payments.build(
      amount: amount,
      payment_method: params[:payment_method].presence || 'cash',
      date_paid: params[:date_paid].presence || Date.today,
      reference_number: params[:reference_number],
      notes: params[:notes],
      status: 'pending_approval',
      reported_by_client: true,
      payer_name: current_user.display_name.presence || @gig.client_display_name,
      currency: @gig.currency || 'USD'
    )

    if params[:receipt_image].present?
      payment.receipt_image.attach(params[:receipt_image])
    end

    payment.audit_reason = "Reporte de abono enviado por el cliente #{current_user.display_name}"

    if payment.save
      AppNotification.create(
        company: @gig.company,
        target_area: 'leaders',
        notification_type: 'payment_alert',
        title: "💳 ¡Nuevo Comprobante de Abono de Cliente!",
        message: "El cliente '#{@gig.client_display_name}' ha enviado un comprobante de abono de $#{view_context.number_with_precision(amount, precision: 2)} (#{payment.payment_method_label}).",
        action_url: "/gigs/#{@gig.id}"
      ) rescue nil

      redirect_to client_gig_path(@gig), notice: "✅ ¡Comprobante de abono enviado con éxito! El equipo organizador lo revisará y confirmará tu saldo a la brevedad."
    else
      redirect_to client_gig_path(@gig), alert: "No se pudo enviar el comprobante: #{payment.errors.full_messages.join(', ')}"
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
