class LandingController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :set_current_tenant, raise: false
  skip_before_action :check_company_subscription!, raise: false

  layout 'landing'

  def index
    if user_signed_in?
      redirect_to authenticated_root_path and return
    end

    @modules = AppModule.all
    @modules_by_category = AppModule.by_category
  end
end
