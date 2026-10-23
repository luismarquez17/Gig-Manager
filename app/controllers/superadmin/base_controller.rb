module Superadmin
  class BaseController < ApplicationController
    before_action :require_superadmin!
    around_action :without_tenant_scope

    layout 'application'

    private

    def without_tenant_scope(&block)
      ::ActsAsTenant.without_tenant(&block)
    end
  end
end
