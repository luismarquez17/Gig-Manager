class CreateGigs < ActiveRecord::Migration[7.1]
  def change
    create_table :gigs do |t|
      t.date :date
      t.decimal :amount
      t.references :client, null: false, foreign_key: true

      t.timestamps
    end
  end
end
