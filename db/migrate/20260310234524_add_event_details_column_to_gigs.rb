class AddEventDetailsColumnToGigs < ActiveRecord::Migration[7.1]
  def change
    add_column :gigs, :details, :text
  end
end
