# Answers "how do we pay this group of people?" — headcount, total cost, the
# spread, and the shape of the distribution.
class PayrollSummaryQuery < PayrollQuery
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

  private

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
end
