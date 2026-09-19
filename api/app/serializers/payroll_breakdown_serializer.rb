class PayrollBreakdownSerializer
  def initialize(breakdown)
    @breakdown = breakdown
  end

  def as_json
    {
      dimension: breakdown.dimension,
      groups: breakdown.rows.map { |row| row_json(row) }
    }
  end

  private

  attr_reader :breakdown

  def row_json(row)
    {
      key: row.key,
      label: row.label,
      headcount: row.headcount,
      total: money(row.total_minor),
      average: money(row.average_minor),
      percentiles: row.percentiles.transform_values { |amount| money(amount) }
    }
  end

  def money(amount_minor)
    return nil if amount_minor.nil?

    MoneySerializer.call(amount_minor: amount_minor, currency: breakdown.currency)
  end
end
