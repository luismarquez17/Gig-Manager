class AddForMusicianToGigTimelineItems < ActiveRecord::Migration[7.1]
  def change
    add_column :gig_timeline_items, :for_musician, :boolean, default: false, null: false
  end
end
