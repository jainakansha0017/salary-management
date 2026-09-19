class CreateCompensations < ActiveRecord::Migration[7.1]
  def change
    create_table :compensations do |t|
      t.references :employee, null: false, foreign_key: true

      # As paid. Integer minor units, never a float (ADR-1).
      t.bigint :amount_minor, null: false
      t.string :currency_code, null: false, limit: 3

      # As compared. Converted at the rate effective on this record's own
      # effective_from, which never changes — so this value can never become
      # stale and is safe to store (ADR-3).
      t.bigint :amount_base_minor, null: false
      t.string :base_currency_code, null: false, limit: 3

      # Kept so any converted figure can be explained and audited later.
      t.decimal :exchange_rate_used, precision: 18, scale: 8, null: false

      t.date :effective_from, null: false
      t.date :effective_to, comment: "null means this is the current salary"

      t.string :reason, null: false
      t.text :note

      t.timestamps
    end

    add_foreign_key :compensations, :currencies, column: :currency_code, primary_key: :code
    add_foreign_key :compensations, :currencies, column: :base_currency_code, primary_key: :code

    add_check_constraint :compensations, "amount_minor > 0", name: "compensations_amount_positive"
    add_check_constraint :compensations, "amount_base_minor > 0", name: "compensations_base_amount_positive"
    add_check_constraint :compensations,
                         "effective_to IS NULL OR effective_to > effective_from",
                         name: "compensations_period_ordered"

    # An employee cannot be on two salaries at once. Enforced in the database
    # because this is the invariant the whole history model rests on, and
    # application-level checks race under concurrency.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          ALTER TABLE compensations
          ADD CONSTRAINT compensations_no_overlapping_periods
          EXCLUDE USING gist (
            employee_id WITH =,
            daterange(effective_from, effective_to, '[)') WITH &&
          )
        SQL
      end

      dir.down do
        execute "ALTER TABLE compensations DROP CONSTRAINT compensations_no_overlapping_periods"
      end
    end

    # "Current salary" is the hot path: the directory joins it for all 10,000
    # employees. A partial unique index makes that an indexed lookup rather
    # than a sort, and states the one-current-record rule explicitly.
    add_index :compensations, :employee_id, unique: true,
              where: "effective_to IS NULL",
              name: "index_one_current_compensation_per_employee"

    # Sorting and filtering the directory by pay reads this single column, with
    # no join to exchange rates — the payoff from storing the base amount.
    add_index :compensations, :amount_base_minor,
              where: "effective_to IS NULL",
              name: "index_current_compensations_on_base_amount"

    # Salary history for one employee, newest first.
    add_index :compensations, [ :employee_id, :effective_from ],
              name: "index_compensations_on_employee_and_start"
  end
end
