class CreateGigUpsellRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :gig_upsell_requests do |t|
      t.references :gig, null: false, foreign_key: true
      t.references :company, null: true, foreign_key: true
      t.string :upsell_key, null: false
      t.string :title, null: false
      t.string :emoji
      t.decimal :price, precision: 12, scale: 2, default: 0.0, null: false
      t.string :currency, default: 'USD', null: false
      t.string :status, default: 'pending', null: false
      t.text :notes
      t.datetime :requested_at
      t.datetime :processed_at

      t.timestamps
    end

    add_index :gig_upsell_requests, :status
    add_index :gig_upsell_requests, [:gig_id, :upsell_key]
  end
end
