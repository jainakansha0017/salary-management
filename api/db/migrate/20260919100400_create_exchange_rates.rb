class CreateExchangeRates < ActiveRecord::Migration[7.1]
  def change
    create_table :exchange_rates do |t|
      # Named *_code rather than *_id because the value really is an ISO 4217
      # code, and calling it an id would hide that.
      t.string :from_currency_code, null: false, limit: 3
      t.string :to_currency_code, null: false, limit: 3

      # Deliberately directional: an amount in from_currency multiplied by rate
      # gives the amount in to_currency. Eight decimal places is enough for
      # pairs with very different magnitudes, such as JPY to GBP.
      t.decimal :rate, precision: 18, scale: 8, null: false

      t.date :effective_from, null: false
      t.date :effective_to, comment: "null means this is the current rate"

      t.timestamps
    end

    add_foreign_key :exchange_rates, :currencies, column: :from_currency_code, primary_key: :code
    add_foreign_key :exchange_rates, :currencies, column: :to_currency_code, primary_key: :code

    add_check_constraint :exchange_rates, "rate > 0", name: "exchange_rates_rate_positive"
    add_check_constraint :exchange_rates,
                         "effective_to IS NULL OR effective_to > effective_from",
                         name: "exchange_rates_period_ordered"

    # A currency pair must not have two rates covering the same day, or a
    # conversion would depend on which row happened to be read first.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          ALTER TABLE exchange_rates
          ADD CONSTRAINT exchange_rates_no_overlapping_periods
          EXCLUDE USING gist (
            from_currency_code WITH =,
            to_currency_code WITH =,
            daterange(effective_from, effective_to, '[)') WITH &&
          )
        SQL
      end

      dir.down do
        execute "ALTER TABLE exchange_rates DROP CONSTRAINT exchange_rates_no_overlapping_periods"
      end
    end

    # Resolving the rate for a pair on a date is the hot path during seeding.
    add_index :exchange_rates, [ :from_currency_code, :to_currency_code, :effective_from ],
              name: "index_exchange_rates_on_pair_and_start"
  end
end
