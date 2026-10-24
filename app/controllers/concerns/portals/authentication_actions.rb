# frozen_string_literal: true

module Portals
  module AuthenticationActions
    extend ActiveSupport::Concern

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
  end
end
