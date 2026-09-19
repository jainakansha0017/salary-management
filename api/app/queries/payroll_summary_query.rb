# Answers "how do we pay this group of people?" — headcount, total cost, the
# spread, and the shape of the distribution.
#
# The population is defined by *compensation*, not by employee status: whoever
# had a salary period in effect on `as_of`. Because a leaver's final period is
# closed on their leaving date, that one rule excludes departed staff for free,
# and it makes the figures answerable for any past date without a second notion
# of who counted as employed then.
#
# Every number here is computed by Postgres (ADR-4). Nothing in this file loads
# a Compensation object — at 10,000 rows the aggregation is cheap and the object
# allocation is not.
class PayrollSummaryQuery
  PERCENTILES = { p10: 0.10, p25: 0.25, median: 0.50, p75: 0.75, p90: 0.90 }.freeze

  # A target, not a guarantee. Band edges are rounded to readable numbers, which
  # is worth a band more or less either way.
  BAND_TARGET = 10

  Summary = Struct.new(
    :headcount, :total_minor, :average_minor, :minimum_minor, :maximum_minor,
    :percentiles, :bands, :currency,
    keyword_init: true
  )

  # `to_minor` is exclusive: a salary exactly on a boundary belongs to the band
  # above, so no one is counted twice.
  Band = Struct.new(:from_minor, :to_minor, :headcount, keyword_init: true)

  def initialize(params = {}, scope: Employee.all, today: Date.current)
    @params = params.to_h.symbolize_keys
    @scope = scope
    @today = today
  end

  def call
    headcount, total, average, minimum, maximum, *percentiles = aggregate

    Summary.new(
      headcount: headcount,
      total_minor: total.to_i,
      average_minor: average&.to_i,
      minimum_minor: minimum,
      maximum_minor: maximum,
      percentiles: PERCENTILES.keys.zip(percentiles.map { |value| value&.round }).to_h,
      bands: distribution(minimum, maximum),
      currency: base_currency
    )
  end

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

  def aggregate
    population.pick(
      Arel.sql("COUNT(*)"),
      # COALESCE so that an empty group reports a payroll cost of zero rather
      # than of nothing — a filter matching no one is not a missing answer.
      Arel.sql("COALESCE(SUM(amount_base_minor), 0)"),
      # AVG over bigint is numeric, so the mean stays exact until we round it.
      Arel.sql("ROUND(AVG(amount_base_minor))"),
      Arel.sql("MIN(amount_base_minor)"),
      Arel.sql("MAX(amount_base_minor)"),
      # percentile_cont interpolates between the two middle salaries, so the
      # median of an even-sized group sits between them rather than picking one
      # arbitrarily. It works in double precision; salaries are far below the
      # 2^53 where that stops being exact, so rounding costs at most half a
      # minor unit.
      *PERCENTILES.each_value.map { |fraction| Arel.sql(percentile_sql(fraction)) }
    )
  end

  def percentile_sql(fraction)
    "percentile_cont(#{fraction}) WITHIN GROUP (ORDER BY amount_base_minor)"
  end

  # Counts per band in one pass. `width_bucket` does the arithmetic in the
  # database, so the histogram costs a single grouped scan rather than 10,000
  # amounts crossing into Ruby to be sorted into buckets.
  def distribution(minimum, maximum)
    return [] if minimum.nil?

    width = band_width(maximum - minimum)
    floor = (minimum / width) * width
    count = ((maximum - floor) / width) + 1
    ceiling = floor + (count * width)

    counts = population.group(
      Arel.sql("width_bucket(amount_base_minor, #{floor}, #{ceiling}, #{count})")
    ).count

    Array.new(count) do |index|
      from = floor + (index * width)
      Band.new(from_minor: from, to_minor: from + width, headcount: counts.fetch(index + 1, 0))
    end
  end

  # Bands land on 10, 20 or 50 thousand rather than on 17,432, because the
  # boundaries are read by a person.
  def band_width(span)
    return 1 if span < BAND_TARGET

    raw = (span / BAND_TARGET) + 1
    magnitude = 10**Math.log10(raw).floor

    [ 1, 2, 5, 10 ].map { |multiple| magnitude * multiple }.find { |width| width >= raw }
  end

  def base_currency
    @base_currency ||= Currency.find(Rails.configuration.x.base_currency_code)
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
