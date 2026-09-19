# What every payroll question has in common: which people, on which date.
#
# The population is defined by *compensation*, not by employee status: whoever
# had a salary period in effect on `as_of`. Because a leaver's final period is
# closed on their leaving date, that one rule excludes departed staff for free,
# and it makes the figures answerable for any past date without a second notion
# of who counted as employed then.
#
# Subclasses decide what to ask of that population. None of them load a
# Compensation object — the aggregation is Postgres's job (ADR-4).
class PayrollQuery
  def initialize(params = {}, scope: Employee.all, today: Date.current)
    @params = params.to_h.symbolize_keys
    @scope = scope
    @today = today
  end

  # Echoed back to the client so it can show what was actually answered, rather
  # than assuming its parameters were understood.
  def applied
    filter.applied.merge(as_of: as_of)
  end

  def as_of
    @as_of ||= parse_date(params[:as_of]) || today
  end

  private

  attr_reader :params, :scope, :today

  def filter
    @filter ||= EmployeeFilter.new(params)
  end

  # A subquery rather than a join: the filters narrow employees, the aggregate
  # runs over compensations, and keeping them separate means the aggregate never
  # sees a duplicated row.
  def population
    @population ||= Compensation
                    .effective_on(as_of)
                    .where(employee_id: filter.apply(scope).select(:id))
  end

  def base_currency
    @base_currency ||= Currency.find(Rails.configuration.x.base_currency_code)
  end

  def percentile_sql(fraction)
    "percentile_cont(#{fraction}) WITHIN GROUP (ORDER BY amount_base_minor)"
  end

  # `Date.iso8601`, not `Date.parse`. The latter is a natural-language guesser —
  # it reads "last tuesday" as a date, and "03/04" as the fourth of March — so a
  # typo would be answered with confident figures for the wrong day.
  #
  # An unrecognised date falls back to today rather than erroring, matching how
  # the directory treats an unknown sort key. `applied` echoes what was used, so
  # the client can tell it was ignored.
  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end
end
