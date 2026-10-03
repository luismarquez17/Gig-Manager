class Current < ActiveSupport::CurrentAttributes
  attribute :company, :user, :ip_address, :audit_reason
end
