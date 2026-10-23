class PortalsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :verify_authenticity_token, only: [:sign_contract, :request_upsell]
  layout 'portal'

  before_action :set_gig

  def show
    @client = @gig.client
    @gig_payments = @gig.company&.module_enabled?(:finances) ? @gig.gig_payments.order(date_paid: :desc) : []
    @timeline_items = @gig.company&.module_enabled?(:gigs) ? @gig.gig_timeline_items.for_client.order(:position, :time) : []
    @staff_members = @gig.company&.module_enabled?(:payroll) ? @gig.staff_members.with_attached_avatar : []
  end

  def access
    @company = @gig.company
    @client = @gig.client

    if user_signed_in?
      if current_user.client? && (current_user.client_id == @gig.client_id || (@gig.client_email.present? && current_user.email.to_s.downcase == @gig.client_email.to_s.downcase))
        redirect_to client_gig_path(@gig), notice: "🎉 ¡Hola #{current_user.display_name}! Has accedido a tu panel de control de evento."
        return
      end
    end

    if @client.nil? && (@gig.client_display_name.present? || @gig.client_email.present?)
      @client = Client.find_or_create_for_gig(
        company: @gig.company,
        name: @gig.client_display_name,
        phone: @gig.client&.phone,
        email: @gig.client_email
      )
      @gig.update_column(:client_id, @client.id) if @client.present? && @gig.client_id != @client.id
    end
  end

  def login
    email = params[:email].to_s.strip.downcase
    password = params[:password].to_s

    if email.blank? || password.blank?
      redirect_to access_public_portal_path(@gig.portal_token), alert: "Por favor ingresa tu correo y contraseña."
      return
    end

    user = User.where("LOWER(email) = ?", email).first

    if user&.valid_password?(password)
      if @gig.client_id.present? && user.client_id.blank? && user.client?
        user.update_column(:client_id, @gig.client_id)
      elsif @gig.client.present? && user.client_id != @gig.client_id && user.client? && (@gig.client_email.to_s.downcase == email || @gig.client.email.to_s.downcase == email)
        user.update_column(:client_id, @gig.client_id)
      end

      sign_in(user)
      if user.client?
        redirect_to client_gig_path(@gig), notice: "🎉 ¡Bienvenido #{user.display_name}! Tienes el control total de tu evento."
      else
        redirect_to authenticated_root_path, notice: "Sesión iniciada con éxito."
      end
    else
      redirect_to access_public_portal_path(@gig.portal_token), alert: "❌ Correo o contraseña incorrectos. Si aún no tienes contraseña, activa tu cuenta abajo."
    end
  end

  def setup_password
    @company = @gig.company
    @client = @gig.client

    email = params[:email].to_s.strip.downcase
    phone = params[:phone].to_s.strip
    password = params[:password].to_s
    password_confirmation = params[:password_confirmation].to_s

    if password.length < 6
      redirect_to access_public_portal_path(@gig.portal_token), alert: "❌ La contraseña debe tener al menos 6 caracteres."
      return
    end

    if password != password_confirmation
      redirect_to access_public_portal_path(@gig.portal_token), alert: "❌ Las contraseñas no coinciden."
      return
    end

    client_target_name = @client&.name.presence || @gig.client_display_name
    client_target_phone = phone.presence || @client&.phone
    client_target_email = email.presence || @gig.client_email || @client&.email

    @client ||= Client.find_or_create_for_gig(
      company: @gig.company,
      name: client_target_name,
      phone: client_target_phone,
      email: client_target_email
    )
    @gig.update_column(:client_id, @client.id) if @client.present? && @gig.client_id != @client.id
    @gig.update_column(:client_email, email) if email.present? && @gig.client_email.blank?

    user = User.find_or_create_client_user(
      company: @gig.company,
      client: @client,
      email: client_target_email,
      name: client_target_name
    )

    if user.present?
      user.email = email if email.present? && !User.where.not(id: user.id).exists?(email: email)
      user.password = password
      user.password_confirmation = password_confirmation
      if user.save
        @client.update_column(:email, user.email) if @client.email != user.email
        sign_in(user)
        redirect_to client_gig_path(@gig), notice: "🔒 ¡Tu cuenta de cliente ha sido activada con éxito! Ahora tienes el control total de tu evento, #{client_target_name.presence || user.display_name}."
      else
        redirect_to access_public_portal_path(@gig.portal_token), alert: "No se pudo activar la cuenta: #{user.errors.full_messages.join(', ')}"
      end
    else
      redirect_to access_public_portal_path(@gig.portal_token), alert: "Ocurrió un error al configurar tu cuenta. Por favor contacta al equipo organizador."
    end
  rescue StandardError => e
    Rails.logger.error("Error en PortalsController#setup_password: #{e.class}: #{e.message}")
    redirect_to access_public_portal_path(@gig.portal_token), alert: "Ocurrió un error inesperado: #{e.message}"
  end

  def payment_receipt
    @payment = @gig.gig_payments.find_by(id: params[:payment_id])
    if @payment.nil?
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
      return
    end
    @company = @gig.company
    @client = @gig.client
    render 'gig_payments/receipt', layout: false
  end

  def worker_profile
    unless @gig.company&.module_enabled?(:payroll)
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
      return
    end

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
      render json: { success: false, error: @gig.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error("Error en PortalsController#sign_contract: #{e.class}: #{e.message}")
    render json: { success: false, error: "Ocurrió un error al firmar el contrato: #{e.message}" }, status: :unprocessable_entity
  end

  def request_upsell
    unless @gig.company&.module_enabled?(:clients_crm)
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
      # Notificar al líder por email (en background para no retrasar la respuesta)
      UpsellMailer.new_upsell_request(req).deliver_later rescue nil

      price_formatted = sprintf("%.2f", req.price.to_f)
      client_name = @gig.client&.name || @gig.contract_signed_name || 'Invitado'
      show_date = @gig.date ? @gig.date.strftime("%d/%m/%Y") : "show"
      show_term = @gig.company&.venue_mode? ? "evento" : "show"

      AppNotification.create(
        company: @gig.company,
        target_area: 'leaders',
        notification_type: 'gig_alert',
        title: "🚀 Solicitud de Adicional: #{req.title}",
        message: "#{client_name} ha solicitado #{req.emoji} #{req.title} ($#{price_formatted} #{req.currency}) para el #{show_term} del #{show_date}.",
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
    end
  rescue StandardError => e
    Rails.logger.error("Error en PortalsController#request_upsell: #{e.class}: #{e.message}")
    render json: { success: false, error: "Ocurrió un error al solicitar el adicional: #{e.message}" }, status: :unprocessable_entity
  end

  def report_payment
    amount = params[:amount].to_s.tr(',', '.').to_f
    if amount <= 0
      redirect_to public_portal_path(@gig.portal_token), alert: "El monto del pago debe ser mayor a 0."
      return
    end

    payer = params[:payer_name].presence || @gig.client_display_name

    payment = @gig.gig_payments.build(
      amount: amount,
      payment_method: params[:payment_method].presence || 'cash',
      date_paid: params[:date_paid].presence || Date.today,
      reference_number: params[:reference_number],
      notes: params[:notes],
      status: 'pending_approval',
      reported_by_client: true,
      payer_name: payer,
      currency: @gig.currency || 'USD'
    )

    if params[:receipt_image].present?
      payment.receipt_image.attach(params[:receipt_image])
    end

    payment.audit_reason = "Reporte de abono enviado por el cliente (Portal Público)"

    if payment.save
      AppNotification.create(
        company: @gig.company,
        target_area: 'leaders',
        notification_type: 'payment_alert',
        title: "💳 ¡Nuevo Comprobante de Abono de Cliente!",
        message: "El cliente '#{@gig.client_display_name}' ha enviado un comprobante de abono de $#{view_context.number_with_precision(amount, precision: 2)} (#{payment.payment_method_label}).",
        action_url: "/gigs/#{@gig.id}"
      ) rescue nil

      redirect_to public_portal_path(@gig.portal_token), notice: "✅ ¡Comprobante de abono enviado con éxito! El equipo organizador lo revisará y confirmará tu saldo a la brevedad."
    else
      redirect_to public_portal_path(@gig.portal_token), alert: "No se pudo enviar el comprobante: #{payment.errors.full_messages.join(', ')}"
    end
  end

  private

  def set_gig
    @gig = Gig.find_by(portal_token: params[:token])
    if @gig.nil?
      render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
    else
      ActsAsTenant.current_tenant = @gig.company
      Current.company = @gig.company
    end
  end
end
