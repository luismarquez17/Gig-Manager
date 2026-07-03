class AddPortalAndTimelineToGigs < ActiveRecord::Migration[7.1]
  class TempGig < ActiveRecord::Base
    self.table_name = 'gigs'
  end

  def change
    add_column :gigs, :portal_token, :string
    add_column :gigs, :contract_signed, :boolean, default: false, null: false
    add_column :gigs, :contract_signed_at, :datetime
    add_column :gigs, :contract_signed_ip, :string
    add_column :gigs, :contract_signed_name, :string

    add_index :gigs, :portal_token, unique: true

    create_table :gig_timeline_items do |t|
      t.references :gig, null: false, foreign_key: { on_delete: :cascade }
      t.string :time
      t.string :title
      t.text :description
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    reversible do |dir|
      dir.up do
        TempGig.reset_column_information
        TempGig.find_each do |gig|
          gig.update_columns(portal_token: SecureRandom.hex(16))
        end
      end
    end
  end
end
