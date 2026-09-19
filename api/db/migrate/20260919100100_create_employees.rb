class CreateEmployees < ActiveRecord::Migration[7.1]
  def change
    create_table :employees do |t|
      t.string :employee_number, null: false
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email, null: false
      t.string :country_code, null: false, limit: 2, comment: "ISO 3166-1 alpha-2"
      t.references :department, null: false, foreign_key: true
      t.string :job_title, null: false
      t.string :job_level, null: false, comment: "pay band; the peer group for comparisons"
      t.date :hired_on, null: false
      t.date :ended_on, comment: "null while employed"

      t.timestamps
    end

    add_index :employees, :employee_number, unique: true
    add_index :employees, :email, unique: true

    # The directory filters on these three dimensions, so each is indexed.
    add_index :employees, :country_code
    add_index :employees, :job_level

    # Analytics almost always scope to current employees, and most employees
    # are current. A partial index keeps that lookup small.
    add_index :employees, :id, where: "ended_on IS NULL", name: "index_employees_on_active"
  end
end
