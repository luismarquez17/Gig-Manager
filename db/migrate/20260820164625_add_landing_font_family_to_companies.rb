class AddLandingFontFamilyToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :landing_font_family, :string, default: "default"
  end
end
