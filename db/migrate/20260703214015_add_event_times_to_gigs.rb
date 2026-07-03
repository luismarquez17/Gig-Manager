class AddEventTimesToGigs < ActiveRecord::Migration[7.1]
  def change
    add_column :gigs, :start_time, :time
    add_column :gigs, :end_time, :time
  end
end
