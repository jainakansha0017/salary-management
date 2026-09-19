class CreateCurrencies < ActiveRecord::Migration[7.1]
  def change
    # The ISO 4217 code is the natural key and is what every other table refers
    # to, so it is the primary key. A surrogate id would add a join without
    # adding meaning.
    create_table :currencies, id: :string, primary_key: :code, limit: 3 do |t|
      t.string :name, null: false
      t.string :symbol, null: false

      # Not every currency has two decimal places — JPY has none. Storing the
      # exponent is what lets integer minor units be rendered correctly.
      t.integer :minor_unit, null: false, default: 2

      t.timestamps
    end

    add_check_constraint :currencies, "minor_unit >= 0 AND minor_unit <= 4", name: "currencies_minor_unit_range"
  end
end
