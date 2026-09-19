# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_09_19_100100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "departments", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_departments_on_name", unique: true
  end

  create_table "employees", force: :cascade do |t|
    t.string "employee_number", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "email", null: false
    t.string "country_code", limit: 2, null: false, comment: "ISO 3166-1 alpha-2"
    t.bigint "department_id", null: false
    t.string "job_title", null: false
    t.string "job_level", null: false, comment: "pay band; the peer group for comparisons"
    t.date "hired_on", null: false
    t.date "ended_on", comment: "null while employed"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_code"], name: "index_employees_on_country_code"
    t.index ["department_id"], name: "index_employees_on_department_id"
    t.index ["email"], name: "index_employees_on_email", unique: true
    t.index ["employee_number"], name: "index_employees_on_employee_number", unique: true
    t.index ["id"], name: "index_employees_on_active", where: "(ended_on IS NULL)"
    t.index ["job_level"], name: "index_employees_on_job_level"
  end

  add_foreign_key "employees", "departments"
end
