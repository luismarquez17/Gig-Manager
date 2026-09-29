class AddBusinessTypeToCompanies < ActiveRecord::Migration[7.1]
  def change
    add_column :companies, :business_type, :string, default: 'music_band', null: false
  end
end
