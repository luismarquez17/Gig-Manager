# frozen_string_literal: true

class AddHoursAddedToGigUpsellRequests < ActiveRecord::Migration[7.1]
  def change
    add_column :gig_upsell_requests, :hours_added, :integer, default: 0, null: false
  end
end
