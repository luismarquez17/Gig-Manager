class ApplicationController < ActionController::Base
  before_action :authenticate_user! # Esto bloquea la app si no has iniciado sesión

  protected

  def require_leader!
    unless current_user&.leader?
      redirect_to root_path, alert: "No tienes permiso para acceder a esta sección."
    end
  end

  def require_staff_or_leader!
    unless current_user&.leader? || current_user&.staff?
      redirect_to root_path, alert: "No tienes permiso para acceder a esta sección."
    end
  end
end