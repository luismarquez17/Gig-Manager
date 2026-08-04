module Superadmin
  class BaseController < ApplicationController
    before_action :require_superadmin!

    layout 'application'
  end
end
