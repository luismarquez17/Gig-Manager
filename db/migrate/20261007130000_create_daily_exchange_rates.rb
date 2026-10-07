class CreateDailyExchangeRates < ActiveRecord::Migration[7.1]
  def change
    create_table :daily_exchange_rates do |t|
      t.date :rate_date, null: false
      t.string :currency_from, default: "USD", null: false
      t.string :currency_to, default: "VES", null: false
      t.decimal :bcv_rate, precision: 16, scale: 4, null: false
      t.decimal :paralelo_rate, precision: 16, scale: 4
      t.string :source, default: "dolarapi_bcv"
      t.datetime :fetched_at, null: false

      t.timestamps
    end

    add_index :daily_exchange_rates, [:rate_date, :currency_from, :currency_to], unique: true, name: "index_daily_exchange_rates_on_date_and_currencies"
  end
end
