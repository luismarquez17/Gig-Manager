class ApplicationController < ActionController::Base
  before_action :authenticate_user! # Esto bloquea la app si no has iniciado sesión
end