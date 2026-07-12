class UsersController < ApplicationController
  before_action :set_user, only: [:show, :edit, :update, :update_role]
  before_action :require_leader!, only: [:index, :update_role]
  before_action :require_profile_viewer_or_self!, only: [:show]
  before_action :require_self_or_leader!, only: [:edit, :update]

  def index
    @users = User.all.order(created_at: :desc)
  end

  def show
  end

  def edit
  end

  def update
    if @user.update(user_params)
      # If client, also update the associated client's phone if provided
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
    if @user.update(role: params[:role])
      redirect_to users_path, notice: "Rol actualizado correctamente para #{@user.email}."
    else
      redirect_to users_path, alert: "Error al actualizar el rol."
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def require_profile_viewer_or_self!
    unless current_user&.leader? || current_user&.staff? || current_user&.client? || current_user == @user
      redirect_to root_path, alert: "No tienes permiso para acceder a esta sección."
    end
  end

  def require_self_or_leader!
    if @user.client?
      # Clients can only edit their own profile
      unless current_user == @user
        redirect_to root_path, alert: "No tienes permiso para acceder a esta sección."
      end
    else
      # Workers can be edited by themselves or a leader
      unless current_user == @user || current_user&.leader?
        redirect_to root_path, alert: "No tienes permiso para acceder a esta sección."
      end
    end
  end

  def user_params
    # We handle client phone separately in the update action to avoid
    # issues with accepts_nested_attributes_for on a belongs_to association.
    params.require(:user).permit(:name, :specialty, :bio, :avatar)
  end
end
