class AddLocationToGigs < ActiveRecord::Migration[7.1]
  def change
    add_column :gigs, :location, :string
  end
end
