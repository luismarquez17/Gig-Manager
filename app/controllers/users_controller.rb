class UsersController < ApplicationController
  before_action :set_user, only: [:show, :edit, :update, :update_role]
  before_action :require_leader!, only: [:index, :create_worker, :update_role]
  before_action :require_profile_viewer_or_self!, only: [:show]
  before_action :require_self_or_leader!, only: [:edit, :update]

  def index
    @users = current_company.users.order(created_at: :desc)
    @new_user = User.new
  end

  def create_worker
    email = params.dig(:user, :email).to_s.strip.downcase
    name = params.dig(:user, :name).to_s.strip
    role = params.dig(:user, :role).to_s.presence || 'staff'
    password = params.dig(:user, :password).to_s.presence

    if email.blank?
      redirect_to users_path, alert: "Debes ingresar un correo electrónico válido."
      return
    end

    unless %w[staff musician leader].include?(role)
      role = 'staff'
    end

    existing_user = User.find_by(email: email)

    if existing_user
      # Vincular usuario existente a la empresa actual y asignar rol
      existing_user.company = current_company
      existing_user.role = role
      existing_user.name = name if name.present?
      if password.present?
        existing_user.password = password
        existing_user.password_confirmation = password
      end

      if existing_user.save
        redirect_to users_path, notice: "¡Trabajador #{existing_user.email} (#{existing_user.display_name}) vinculado exitosamente a #{current_company.name} como #{existing_user.role.capitalize}!"
      else
        redirect_to users_path, alert: "No se pudo vincular al trabajador: #{existing_user.errors.full_messages.to_sentence}"
      end
    else
      temp_password = password.presence || SecureRandom.hex(6)
      new_user = User.new(
        email: email,
        name: name.presence || email.split('@').first.capitalize,
        role: role,
        company: current_company,
        password: temp_password,
        password_confirmation: temp_password
      )

      if new_user.save
        redirect_to users_path, notice: "¡Trabajador #{new_user.email} (#{new_user.display_name}) agregado exitosamente a #{current_company.name} como #{new_user.role.capitalize}!"
      else
        redirect_to users_path, alert: "No se pudo agregar al trabajador: #{new_user.errors.full_messages.to_sentence}"
      end
    end
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
    params.require(:user).permit(:name, :specialty, :bio, :avatar, :avatar_base64, :password, :password_confirmation)
  end
end
