class CreateSongsAndGigReviewsAndAddMusicPreferences < ActiveRecord::Migration[7.1]
  def change
    create_table :songs do |t|
      t.references :company, null: false, foreign_key: true
      t.string :title, null: false
      t.string :artist
      t.string :genre, default: 'General'
      t.boolean :active, default: true, null: false

      t.timestamps
    end
    add_index :songs, [:company_id, :genre]

    create_table :gig_reviews do |t|
      t.references :gig, null: false, foreign_key: true
      t.string :client_name
      t.integer :rating, default: 5, null: false
      t.text :comment
      t.boolean :is_client, default: false, null: false
      t.boolean :approved, default: true, null: false
      t.boolean :pinned, default: false, null: false

      t.timestamps
    end
    add_index :gig_reviews, [:gig_id, :approved]

    add_column :gigs, :music_preferences, :jsonb, default: {}
  end
end
