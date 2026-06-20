class AddPackingColumnsToGigItems < ActiveRecord::Migration[7.1]
  def change
    add_column :gig_items, :loaded_quantity, :integer, default: 0, null: false
    add_column :gig_items, :returned_quantity, :integer, default: 0, null: false
  end
end
