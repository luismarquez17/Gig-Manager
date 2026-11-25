# frozen_string_literal: true

module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    skip_before_action :verify_authenticity_token, only: [:google_oauth2, :failure]

    def google_oauth2
      auth = request.env['omniauth.auth']

      if auth.blank? || auth.info.blank? || auth.info.email.blank?
        redirect_to new_user_session_path, alert: "No se pudo obtener la información de tu cuenta de Google."
        return
      end

      pending_plan = session.delete(:pending_signup_plan)
      pending_modules = session.delete(:pending_signup_modules)

      @user = User.from_omniauth(auth, plan: pending_plan, modules: pending_modules)

      if @user&.persisted?
        flash[:notice] = "Has iniciado sesión exitosamente con Google."
        sign_in_and_redirect @user, event: :authentication
      else
        session['devise.google_data'] = auth.except('extra')
        error_msg = @user ? @user.errors.full_messages.join(', ') : "Error al procesar el usuario."
        redirect_to new_user_registration_path, alert: "No se pudo iniciar sesión con Google: #{error_msg}"
      end
    end

    def failure
      redirect_to new_user_session_path, alert: "Inicio de sesión con Google cancelado o fallido. Por favor, intenta de nuevo."
    end
  end
end
