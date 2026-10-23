# frozen_string_literal: true

class AddScheduledPlanFieldsToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :scheduled_plan_tier, :string
    add_column :companies, :scheduled_modules, :jsonb
    add_column :companies, :scheduled_change_at, :datetime

    add_index :companies, :scheduled_change_at
  end
end
