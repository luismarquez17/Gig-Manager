class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :set_current_tenant
  before_action :check_company_subscription!

  helper_method :current_company, :superadmin?

  def current_company
    Current.company ||= find_or_create_default_company
  end

  def superadmin?
    current_user&.superadmin?
  end

  protected

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
    return if controller_name == 'subscriptions' || controller_name == 'stripe_webhooks'
    return if devise_controller?

    if current_company.present?
      if current_company.suspended?
        redirect_to suspended_company_path
      elsif !current_company.access_granted?
        redirect_to subscriptions_path, alert: "Tu período de prueba de 30 días ha finalizado. Activa tu suscripción para continuar."
      end
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
end