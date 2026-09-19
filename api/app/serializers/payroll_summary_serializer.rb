class PayrollSummarySerializer
  def initialize(summary)
    @summary = summary
  end

  def as_json
    {
      headcount: summary.headcount,
      total: money(summary.total_minor),
      average: money(summary.average_minor),
      minimum: money(summary.minimum_minor),
      maximum: money(summary.maximum_minor),
      percentiles: summary.percentiles.transform_values { |amount| money(amount) },
      distribution: summary.bands.map { |band| band_json(band) }
    }
  end

  private

  attr_reader :summary

  def band_json(band)
    {
      from: money(band.from_minor),
      to: money(band.to_minor),
      headcount: band.headcount
    }
  end

  # Null rather than zero when there is no one to average: an empty group has no
  # median, and reporting 0 would draw a bar at the bottom of the chart.
  def money(amount_minor)
    return nil if amount_minor.nil?

    MoneySerializer.call(amount_minor: amount_minor, currency: summary.currency)
  end
end
