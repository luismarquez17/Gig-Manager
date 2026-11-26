class ApplicationController < ActionController::Base
  layout :layout_by_resource
  before_action :set_request_context
  before_action :authenticate_user!
  before_action :set_current_tenant
  before_action :check_company_subscription!
  before_action :ensure_company_onboarding!

  helper_method :current_company, :superadmin?, :module_enabled?

  def current_company
    Current.company ||= find_or_create_default_company
  end

  def superadmin?
    current_user&.superadmin?
  end

  def module_enabled?(module_key)
    return true if current_user&.superadmin?
    current_company.present? ? current_company.module_enabled?(module_key) : true
  end

  protected

  def layout_by_resource
    if devise_controller? && !user_signed_in?
      "landing"
    else
      "application"
    end
  end

  def after_sign_out_path_for(resource_or_scope)
    public_landing_path
  end

  def after_sign_in_path_for(resource_or_scope)
    if resource_or_scope.is_a?(User) && resource_or_scope.leader? && !resource_or_scope.superadmin? && resource_or_scope.company&.onboarding_pending?
      welcome_onboarding_path
    else
      authenticated_root_path
    end
  end

  def set_request_context
    Current.ip_address = request.remote_ip rescue nil
  end

  def set_current_tenant
    return unless user_signed_in?

    Current.user = current_user

    if current_user.superadmin?
      if session[:superadmin_company_id].present?
        target_company = Company.find_by(id: session[:superadmin_company_id])
      end
      Current.company = target_company || current_user.company || find_or_create_default_company
    else
      Current.company = current_user.company || find_or_create_default_company
      if current_user.company_id.blank?
        current_user.update_column(:company_id, Current.company.id)
      end
    end

    ::ActsAsTenant.current_tenant = Current.company
  end

  def check_company_subscription!
    return unless user_signed_in?
    return if current_user.superadmin?
    return if controller_name == 'pages' && action_name == 'suspended'
    return if controller_name == 'subscriptions' || controller_name == 'stripe_webhooks' || controller_name == 'company_onboarding'
    return if devise_controller?

    # Solo los líderes de la empresa son evaluados por la suscripción SaaS.
    # Los clientes, staff y músicos no deben ver bloqueos ni avisos de cobro de la empresa.
    return unless current_user.leader?

    if current_company.present?
      # Evaluar el ciclo de vida (recordatorio a los 28 días, período de gracia a los 30 días, suspensión a los 33 días)
      current_company.check_subscription_lifecycle!

      if current_company.suspended? || !current_company.access_granted?
        if request.format.json? || request.xhr?
          render json: { reply: "⚠️ La cuenta de tu empresa se encuentra temporalmente suspendida por pago pendiente. Tus datos están 100% a salvo.", error: "company_suspended" }, status: :payment_required
        else
          redirect_to suspended_company_path
        end
      end
    end
  end

  def ensure_company_onboarding!
    return unless user_signed_in?
    return if current_user.superadmin?
    return unless current_user.leader?
    return if devise_controller?
    return if controller_name.in?(%w[company_onboarding subscriptions stripe_webhooks])
    return if controller_name == 'pages' && action_name == 'suspended'
    return if request.format.json? || request.xhr?

    if current_company&.onboarding_pending?
      redirect_to welcome_onboarding_path
    end
  end

  def find_or_create_default_company
    Company.first || Company.create!(name: "Empresa Principal", slug: "principal-#{SecureRandom.hex(4)}", monthly_fee: 0.0)
  end

  def require_superadmin!
    unless current_user&.superadmin?
      redirect_to root_path, alert: "Acceso denegado: Se requieren permisos de Superadmin."
    end
  end

  def require_leader!
    unless current_user&.superadmin? || current_user&.leader?
      redirect_to root_path, alert: "No tienes permiso para acceder a esta sección."
    end
  end

  def require_staff_or_leader!
    unless current_user&.superadmin? || current_user&.leader? || current_user&.staff? || current_user&.musician?
      redirect_to root_path, alert: "No tienes permiso para acceder a esta sección."
    end
  end

  def require_module!(module_key)
    return if current_user&.superadmin?

    unless module_enabled?(module_key)
      module_name = AppModule.name_for(module_key)
      redirect_to root_path, alert: "El módulo de #{module_name} no está activo en el plan de tu empresa. Contacta a un administrador para habilitarlo."
    end
  end
end