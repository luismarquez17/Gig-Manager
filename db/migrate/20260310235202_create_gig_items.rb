class CreateGigItems < ActiveRecord::Migration[7.1]
  def change
    create_table :gig_items do |t|
      t.references :gig, null: false, foreign_key: true
      t.references :item, null: false, foreign_key: true
      t.integer :quantity, default: 1
      t.boolean :checked, default: false

      t.timestamps
    end
  end
end
