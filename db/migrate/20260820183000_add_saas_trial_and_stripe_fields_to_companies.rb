class AddSaasTrialAndStripeFieldsToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :trial_started_at, :datetime
    add_column :companies, :trial_ends_at, :datetime
    add_column :companies, :stripe_customer_id, :string
    add_column :companies, :stripe_subscription_id, :string
    add_column :companies, :stripe_price_id, :string
    add_column :companies, :subscription_status, :string, default: "trialing", null: false
    add_column :companies, :plan_tier, :string, default: "starter", null: false

    add_index :companies, :stripe_customer_id
    add_index :companies, :stripe_subscription_id
    add_index :companies, :subscription_status
  end
end
