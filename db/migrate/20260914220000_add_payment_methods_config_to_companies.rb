# frozen_string_literal: true

class AddPaymentMethodsConfigToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :payment_methods_config, :jsonb, default: {}, null: false
  end
end
