class FinanceSetting < ApplicationRecord
  include TenantScoped

  def self.instance
    if Current.company.present?
      where(company_id: Current.company.id).first_or_create!
    else
      first_or_create!
    end
  end


  def reinvest_rate_float
    reinvest_rate.to_f
  end
end
