module Users
  class RegistrationsController < Devise::RegistrationsController
    layout 'landing'

    def new
      build_resource({})
      @selected_modules = params[:modules].to_s.split(',').map(&:strip).reject(&:blank?)
      @company_name = params[:company_name]
      yield resource if block_given?
      respond_with resource
    end

    def create
      build_resource(sign_up_params)

      resource.company_name_input = params[:company_name].presence || params.dig(:user, :company_name_input)
      resource.selected_modules_input = params[:modules].presence || params.dig(:user, :selected_modules_input)

      resource.save
      yield resource if block_given?
      if resource.persisted?
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
        @selected_modules = params[:modules].to_s.split(',').map(&:strip).reject(&:blank?)
        @company_name = params[:company_name]
        respond_with resource
      end
    end

    protected

    def sign_up_params
      params.require(:user).permit(:name, :email, :password, :password_confirmation, :company_name_input, :selected_modules_input)
    end
  end
end
