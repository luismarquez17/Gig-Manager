class AddCustomUpsellsToGigs < ActiveRecord::Migration[7.1]
  def change
    add_column :gigs, :custom_upsells, :jsonb, default: {}
  end
end
