class AddSearchIndexToEmployees < ActiveRecord::Migration[7.1]
  # HR searches by fragments — "kowal", part of an email, the tail of an
  # employee number — so the query is `ILIKE '%term%'`. A leading wildcard makes
  # a btree index useless, which leaves a sequential scan over every employee.
  #
  # A trigram GIN index over the concatenation of the four searchable columns
  # answers all of them with one index instead of four. It has to be built on
  # exactly the expression the query uses, so it is defined here and in
  # Employee::SEARCHABLE_TEXT; the spec for Employee.search asserts the planner
  # actually reaches for it, which is what stops the two drifting apart.
  SEARCHABLE_TEXT =
    "(first_name || ' ' || last_name || ' ' || email || ' ' || employee_number)".freeze

  def change
    enable_extension "pg_trgm"

    add_index :employees, "#{SEARCHABLE_TEXT} gin_trgm_ops",
              using: :gin,
              name: "index_employees_on_searchable_text"
  end
end
