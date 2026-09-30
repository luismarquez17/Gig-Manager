class UsersController < ApplicationController
  before_action :set_user, only: [:show, :edit, :update, :update_role, :claim_account]
  before_action :require_leader!, only: [:index, :create_worker, :update_role, :claim_account]
  before_action :require_profile_viewer_or_self!, only: [:show]
  before_action :require_self_or_leader!, only: [:edit, :update]

  def index
    @users = current_company.users.order(is_eventual: :asc, created_at: :desc)
    @new_user = User.new
  end

  def create_worker
    is_eventual = params[:eventual] == '1' || params.dig(:user, :is_eventual) == '1' || params.dig(:user, :email).blank?
    email = params.dig(:user, :email).to_s.strip.downcase
    name = params.dig(:user, :name).to_s.strip
    role = params.dig(:user, :role).to_s.presence || 'staff'
    phone = params.dig(:user, :phone).to_s.strip.presence
    specialty = params.dig(:user, :specialty).to_s.strip.presence
    password = params.dig(:user, :password).to_s.presence

    unless %w[staff musician leader].include?(role)
      role = 'staff'
    end

    if is_eventual && email.blank?
      if name.blank?
        redirect_to users_path, alert: "Debes ingresar al menos el nombre del trabajador eventual."
        return
      end

      worker = User.create_eventual_worker!(
        company: current_company,
        name: name,
        role: role,
        phone: phone,
        specialty: specialty
      )

      redirect_to users_path, notice: "⚡ Trabajador eventual '#{worker.display_name}' agregado exitosamente a #{current_company.name} como #{worker.role.capitalize}. ¡Listo para asignar en eventos y nómina!"
      return
    end

    if email.blank?
      redirect_to users_path, alert: "Debes ingresar un correo electrónico válido o registrar como trabajador eventual."
      return
    end

    existing_user = User.find_by(email: email)

    if existing_user
      # Vincular usuario existente a la empresa actual y asignar rol
      existing_user.company = current_company
      existing_user.role = role
      existing_user.name = name if name.present?
      existing_user.phone = phone if phone.present?
      existing_user.specialty = specialty if specialty.present?
      existing_user.is_eventual = false
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
        phone: phone,
        specialty: specialty,
        company: current_company,
        is_eventual: false,
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

  def claim_account
    new_email = params.dig(:user, :email).to_s.strip.downcase
    new_password = params.dig(:user, :password).to_s.presence
    new_name = params.dig(:user, :name).to_s.strip.presence || @user.name

    if new_email.blank?
      redirect_to users_path, alert: "Debes ingresar un correo electrónico válido para habilitar el inicio de sesión."
      return
    end

    if new_password.blank? || new_password.length < 6
      redirect_to users_path, alert: "La contraseña debe tener al menos 6 caracteres."
      return
    end

    existing = User.where.not(id: @user.id).find_by(email: new_email)
    if existing
      redirect_to users_path, alert: "El correo #{new_email} ya pertenece a otra cuenta en el sistema."
      return
    end

    @user.claim_account!(new_email, new_password, new_name)
    redirect_to users_path, notice: "🎉 ¡Acceso habilitado con éxito para #{@user.display_name}! Ahora puede iniciar sesión con #{new_email}."
  rescue => e
    redirect_to users_path, alert: "No se pudo habilitar la cuenta: #{e.message}"
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
    permitted = [:name, :phone, :specialty, :bio, :avatar, :avatar_base64, :password, :password_confirmation]
    permitted << :email if current_user&.leader? || current_user&.superadmin? || @user&.eventual?
    permitted << :is_eventual if current_user&.leader? || current_user&.superadmin?
    params.require(:user).permit(permitted)
  end
end
