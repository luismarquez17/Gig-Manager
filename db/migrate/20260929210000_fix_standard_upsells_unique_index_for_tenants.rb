class FixStandardUpsellsUniqueIndexForTenants < ActiveRecord::Migration[7.1]
  def change
    if index_exists?(:standard_upsells, :key, name: 'index_standard_upsells_on_key')
      remove_index :standard_upsells, name: 'index_standard_upsells_on_key'
    end

    unless index_exists?(:standard_upsells, [:company_id, :key], name: 'index_standard_upsells_on_company_id_and_key')
      add_index :standard_upsells, [:company_id, :key], unique: true, name: 'index_standard_upsells_on_company_id_and_key'
    end
  end
end
