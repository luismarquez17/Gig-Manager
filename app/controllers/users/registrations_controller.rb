module Users
  class RegistrationsController < Devise::RegistrationsController
    layout 'landing'

    def new
      build_resource({})
      resolve_plan_and_modules_selection
      @company_name = params[:company_name]
      yield resource if block_given?
      respond_with resource
    end

    def create
      build_resource(sign_up_params)

      resource.company_name_input = params[:company_name].presence || params.dig(:user, :company_name_input)
      resource.selected_plan_input = params[:plan].presence || params.dig(:user, :selected_plan_input).presence || session[:pending_signup_plan]
      resource.selected_modules_input = params[:modules].presence || params.dig(:user, :selected_modules_input).presence || session[:pending_signup_modules]

      resource.save
      yield resource if block_given?
      if resource.persisted?
        session.delete(:pending_signup_plan)
        session.delete(:pending_signup_modules)

        if resource.active_for_authentication?
          set_flash_message! :notice, :signed_up
          sign_up(resource_name, resource)
          respond_with resource, location: after_sign_up_path_for(resource)
        else
          set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
          expire_data_after_sign_in!
          respond_with resource, location: after_inactive_sign_up_path_for(resource)
        end
      else
        clean_up_passwords resource
        set_minimum_password_length
        resolve_plan_and_modules_selection
        @company_name = params[:company_name]
        respond_with resource
      end
    end

    protected

    def after_sign_up_path_for(resource)
      if resource.leader? && !resource.superadmin? && resource.company&.onboarding_pending?
        welcome_onboarding_path
      else
        authenticated_root_path
      end
    end

    def sign_up_params
      params.require(:user).permit(:name, :email, :password, :password_confirmation, :company_name_input, :selected_modules_input, :selected_plan_input)
    end

    private

    def resolve_plan_and_modules_selection
      raw_plan = params[:plan].presence || session[:pending_signup_plan].presence || 'banda'
      @selected_plan = Company::VALID_PLAN_TIERS.include?(raw_plan.to_s) ? raw_plan.to_s : 'banda'

      raw_modules = params[:modules].presence || session[:pending_signup_modules]
      @selected_modules = raw_modules.to_s.split(',').map(&:strip).reject(&:blank?)
      if @selected_modules.empty? && @selected_plan != 'personalizado'
        @selected_modules = AppModule.modules_for_package(@selected_plan)
      elsif @selected_modules.empty?
        @selected_modules = %w[gigs payroll finances]
      end

      @selected_pricing = AppModule.calculate_pricing(@selected_plan, @selected_modules)
      session[:pending_signup_plan] = @selected_plan
      session[:pending_signup_modules] = @selected_modules.join(',')
    end
  end
end
