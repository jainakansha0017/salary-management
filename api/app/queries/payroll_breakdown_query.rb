# The same payroll question as PayrollSummaryQuery, asked once per country,
# department or job level.
#
# This is the view that makes inequity visible: a median that is well below its
# peers, or a job level whose quartiles overlap the one beneath it, is a fact
# about a group that no individual record shows.
class PayrollBreakdownQuery < PayrollQuery
  # Unknown dimensions are refused, not defaulted. Elsewhere a bad parameter is
  # a view preference the server can sensibly ignore; here it *is* the question,
  # and quietly answering a different one would be worse than an error.
  class UnknownDimension < ArgumentError; end

  # An allow-list, not a convenience. The value arrives from the internet and
  # goes into a GROUP BY.
  DIMENSIONS = {
    "country" => "employees.country_code",
    "department" => "employees.department_id",
    "job_level" => "employees.job_level"
  }.freeze

  # Fewer than the summary reports. A breakdown table is read across, and the
  # quartile spread beside the median is what shows a compressed or stretched
  # band; the full set is one drill-down away, from /summary with this group's
  # filter applied.
  PERCENTILES = { p25: 0.25, median: 0.50, p75: 0.75 }.freeze

  Row = Struct.new(
    :key, :label, :headcount, :total_minor, :average_minor, :percentiles,
    keyword_init: true
  )

  Breakdown = Struct.new(:dimension, :rows, :currency, keyword_init: true)

  def call
    Breakdown.new(dimension: dimension, rows: rows, currency: base_currency)
  end

  def applied
    super.merge(dimension: dimension)
  end

  def dimension
    @dimension ||= params[:dimension].to_s.tap do |key|
      next if DIMENSIONS.key?(key)

      raise UnknownDimension, "dimension must be one of: #{DIMENSIONS.keys.join(', ')}"
    end
  end

  private

  def rows
    grouped = aggregate
    names = labels(grouped.map(&:first))

    grouped
      .map { |key, *figures| row_for(key, names.fetch(key, key.to_s), figures) }
      # Largest cost centre first: that is the order the question is asked in.
      # The key breaks ties so two equally expensive groups do not swap places
      # between requests.
      .sort_by { |row| [ -row.total_minor, row.key.to_s ] }
  end

  def aggregate
    population
      .joins(:employee)
      .group(Arel.sql(group_expression))
      .pluck(
        Arel.sql(group_expression),
        Arel.sql("COUNT(*)"),
        Arel.sql("COALESCE(SUM(amount_base_minor), 0)"),
        Arel.sql("ROUND(AVG(amount_base_minor))"),
        *PERCENTILES.each_value.map { |fraction| Arel.sql(percentile_sql(fraction)) }
      )
  end

  def row_for(key, label, figures)
    headcount, total, average, *percentiles = figures

    Row.new(
      key: key,
      label: label,
      headcount: headcount,
      total_minor: total.to_i,
      average_minor: average&.to_i,
      percentiles: PERCENTILES.keys.zip(percentiles.map { |value| value&.round }).to_h
    )
  end

  # Departments group by id — names are not unique and are editable — so the
  # names are resolved afterwards in one query, rather than by widening the
  # aggregate into a third table.
  def labels(keys)
    return {} unless dimension == "department"

    Department.where(id: keys).pluck(:id, :name).to_h
  end

  def group_expression
    DIMENSIONS.fetch(dimension)
  end
end
