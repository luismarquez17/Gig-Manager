class FinanceSetting < ApplicationRecord
  def self.instance
    first_or_create!
  end

  def reinvest_rate_float
    reinvest_rate.to_f
  end
end
