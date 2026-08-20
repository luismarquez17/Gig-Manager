require 'acts_as_tenant'

ActsAsTenant.configure do |config|
  config.require_tenant = false
end
