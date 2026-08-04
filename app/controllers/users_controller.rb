class UsersController < ApplicationController
  before_action :set_user, only: [:show, :edit, :update, :update_role]
  before_action :require_leader!, only: [:index, :update_role]
  before_action :require_profile_viewer_or_self!, only: [:show]
  before_action :require_self_or_leader!, only: [:edit, :update]

  def index
    @users = current_company.users.order(created_at: :desc)
  end

  def show
  end

  def edit
  end

  def update
    avatar_file = params.dig(:user, :avatar)
    if avatar_file.respond_to?(:read)
      content_type = avatar_file.content_type.presence || 'image/jpeg'
      encoded = Base64.strict_encode64(avatar_file.read)
      @user.avatar_base64 = "data:#{content_type};base64,#{encoded}"
      avatar_file.rewind if avatar_file.respond_to?(:rewind)
    end

    filtered_params = user_params
    if filtered_params[:password].blank?
      filtered_params.delete(:password)
      filtered_params.delete(:password_confirmation)
    end

    if @user.update(filtered_params)
      if @user.client? && @user.client.present?
        client_phone = params.dig(:user, :client_phone)
        if client_phone.present?
          @user.client.update(phone: client_phone)
        end
      end
      path = current_user.leader? ? users_path : root_path
      redirect_to path, notice: "Perfil de #{@user.email} actualizado correctamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def update_role
    requested_role = params[:role].to_s

    if requested_role == "superadmin" && !current_user.superadmin?
      redirect_to users_path, alert: "Solo un Superadmin puede asignar el rol de Superadmin."
      return
    end

    if requested_role == "leader" && !current_user.superadmin?
      redirect_to users_path, alert: "Solo el Superadmin puede asignar el rol de Leader/Jefe de empresa."
      return
    end

    if @user.update(role: requested_role)
      redirect_to users_path, notice: "Rol actualizado correctamente para #{@user.email}."
    else
      redirect_to users_path, alert: "Error al actualizar el rol."
    end
  end

  private

  def set_user
    @user = current_user.superadmin? ? User.find(params[:id]) : current_company.users.find(params[:id])
  end

  def require_profile_viewer_or_self!
    unless current_user&.superadmin? || current_user&.leader? || current_user&.staff? || current_user&.client? || current_user == @user
      redirect_to root_path, alert: "No tienes permiso para acceder a esta sección."
    end
  end

  def require_self_or_leader!
    if @user.client?
      unless current_user == @user || current_user&.superadmin?
        redirect_to root_path, alert: "No tienes permiso para acceder a esta sección."
      end
    else
      unless current_user == @user || current_user&.leader? || current_user&.superadmin?
        redirect_to root_path, alert: "No tienes permiso para acceder a esta sección."
      end
    end
  end

  def user_params
    params.require(:user).permit(:name, :specialty, :bio, :avatar, :password, :password_confirmation)
  end
end
