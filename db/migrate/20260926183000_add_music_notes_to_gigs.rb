class AddMusicNotesToGigs < ActiveRecord::Migration[7.1]
  def change
    add_column :gigs, :music_notes, :text
  end
end
