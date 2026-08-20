class AddLandingTemplateAndGradientStyleToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :landing_template, :string, default: "classic_stage"
    add_column :companies, :landing_gradient_style, :string, default: "linear_neon"
  end
end
