class MakeClientQuotesFieldsNullableAndAddPreset < ActiveRecord::Migration[7.1]
  def change
    change_column_null :client_quotes, :client_name, true
    change_column_null :client_quotes, :client_email, true
    change_column_null :client_quotes, :client_phone, true

    add_reference :client_quotes, :preset_budget, foreign_key: true, null: true, index: true
    add_column :client_quotes, :package_name, :string
  end
end
