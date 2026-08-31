class CreateClientQuotes < ActiveRecord::Migration[7.1]
  def change
    create_table :client_quotes do |t|
      t.references :company, foreign_key: true, index: true
      t.references :client, foreign_key: true, null: true, index: true
      t.references :gig, foreign_key: true, null: true, index: true
      t.string :client_name, null: false
      t.string :client_email, null: false
      t.string :client_phone, null: false
      t.string :event_type
      t.date :event_date
      t.string :event_location
      t.time :start_time
      t.time :end_time
      t.decimal :amount, precision: 12, scale: 2, default: 0.0
      t.string :currency, default: "USD"
      t.decimal :advance_amount, precision: 12, scale: 2, default: 0.0
      t.text :details
      t.string :status, null: false, default: "pending"
      t.string :public_token, null: false

      t.timestamps
    end

    add_index :client_quotes, :status
    add_index :client_quotes, :public_token, unique: true
  end
end
