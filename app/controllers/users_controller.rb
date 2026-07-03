class UsersController < ApplicationController
  before_action :require_leader!

  def index
    @users = User.all.order(created_at: :desc)
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:id])
    if @user.update(user_params)
      redirect_to users_path, notice: "Perfil de #{@user.email} actualizado correctamente."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def update_role
    @user = User.find(params[:id])
    if @user.update(role: params[:role])
      redirect_to users_path, notice: "Rol actualizado correctamente para #{@user.email}."
    else
      redirect_to users_path, alert: "Error al actualizar el rol."
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :specialty, :bio, :avatar)
  end
end
