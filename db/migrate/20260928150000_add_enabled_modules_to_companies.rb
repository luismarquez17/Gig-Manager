class AddEnabledModulesToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :enabled_modules, :jsonb, default: {}, null: false
  end
end
