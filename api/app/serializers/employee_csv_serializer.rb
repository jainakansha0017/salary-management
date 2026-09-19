require "csv"

# The directory as a spreadsheet.
#
# It is handed the same relation the list page is built from, so an export and
# the screen it was taken from hold the same people in the same order. The one
# thing that deliberately differs is how money is written down. JSON sends
# minor units and lets the browser format them (ADR-6), because a JSON number
# is a double and the client has `Intl.NumberFormat`. A CSV is opened by a
# person who wants to sum a column, so the amount is written in major units
# with that currency's own number of decimals, and the code travels in its own
# column so the sheet can still be filtered and pivoted by it.
#
# No ActiveRecord objects are built. Ten thousand employees with their pay is
# one `pluck` of scalars rather than twenty thousand model instances — ADR-4's
# argument applied to export rather than to aggregation.
class EmployeeCsvSerializer
  HEADERS = %w[
    employee_number first_name last_name email country_code department
    job_title job_level hired_on ended_on active
    salary salary_currency salary_in_base_currency base_currency
    salary_effective_from
  ].freeze

  COLUMNS = [
    "employees.employee_number",
    "employees.first_name",
    "employees.last_name",
    "employees.email",
    "employees.country_code",
    "departments.name",
    "employees.job_title",
    "employees.job_level",
    "employees.hired_on",
    "employees.ended_on",
    "compensations.amount_minor",
    "compensations.currency_code",
    "compensations.amount_base_minor",
    "compensations.base_currency_code",
    "compensations.effective_from"
  ].freeze

  # A spreadsheet treats a cell beginning with one of these as a formula, so a
  # name entered into the HR system as `=HYPERLINK("http://…"&A1)` would run
  # the moment the export is opened, exfiltrating the row it sits in. Leading
  # apostrophe makes the cell literal text. Applied only to the free-text
  # columns, so dates and amounts are still dates and amounts.
  FORMULA_TRIGGER = /\A[=+\-@\t\r]/

  def initialize(relation)
    @relation = relation
  end

  # One string rather than a stream. Measured against the full seed, every
  # employee in the organisation is 1.5 MB built in 180-260 ms, about half of
  # which is the single `pluck`. Streaming that would buy nothing and cost a
  # held connection plus the inability to report an error once the headers have
  # gone out. The trade flips somewhere in the hundreds of thousands of rows,
  # which is the same scale at which ADR-4's rollups start to pay.
  def call
    CSV.generate do |csv|
      csv << HEADERS
      rows.each { |values| csv << row(values) }
    end
  end

  private

  attr_reader :relation

  # The joins belong here rather than in the query: they exist because of the
  # columns this file wants, not because of how the directory is filtered.
  # `left_joins` so that someone with no pay in effect still appears, with
  # blank salary cells rather than no row.
  def rows
    relation.joins(:department).left_joins(:effective_compensation).pluck(*COLUMNS)
  end

  def row(values)
    number, first_name, last_name, email, country_code, department,
      job_title, job_level, hired_on, ended_on,
      amount_minor, currency_code, base_minor, base_code, effective_from = values

    [
      literal(number), literal(first_name), literal(last_name), literal(email),
      country_code, literal(department), literal(job_title), literal(job_level),
      hired_on, ended_on,
      # Mirrors the `active` field in the JSON row, so the two cannot answer
      # the same question differently.
      ended_on.nil?,
      major(amount_minor, currency_code), currency_code,
      major(base_minor, base_code), base_code,
      effective_from
    ]
  end

  # Integer arithmetic all the way down: dividing by the subunit factor in
  # anything that can become a float would undo the reason money is stored as
  # minor units at all (ADR-1). Blank rather than zero when nobody is being
  # paid — a leaver is not someone earning nothing.
  def major(amount_minor, currency_code)
    return nil if amount_minor.nil?

    exponent = minor_units.fetch(currency_code)
    return amount_minor.to_s if exponent.zero?

    units, subunits = amount_minor.divmod(10**exponent)
    "#{units}.#{subunits.to_s.rjust(exponent, '0')}"
  end

  # Currencies are a handful of rows and every employee shares a few of them,
  # so they are read once here instead of joined twice per row.
  def minor_units
    @minor_units ||= Currency.pluck(:code, :minor_unit).to_h
  end

  def literal(value)
    return value unless value.is_a?(String) && value.match?(FORMULA_TRIGGER)

    "'#{value}"
  end
end
