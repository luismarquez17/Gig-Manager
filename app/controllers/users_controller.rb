class UsersController < ApplicationController
  before_action :require_leader!

  def index
    @users = User.all.order(created_at: :desc)
  end

  def update_role
    @user = User.find(params[:id])
    if @user.update(role: params[:role])
      redirect_to users_path, notice: "Rol actualizado correctamente para #{@user.email}."
    else
      redirect_to users_path, alert: "Error al actualizar el rol."
    end
  end
end
