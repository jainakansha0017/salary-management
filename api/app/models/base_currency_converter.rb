# Converts an amount into the organisation's base currency using the rate that
# was effective on a given date.
#
# A plain object rather than an ActiveRecord model: it holds no state of its
# own, it just applies the rule from ADR-3 in one place so that the write path
# and the seed script cannot drift apart.
class BaseCurrencyConverter
  Result = Struct.new(:amount_minor, :currency_code, :rate, keyword_init: true)

  def self.call(amount_minor:, from:, on:, base: Rails.configuration.x.base_currency_code)
    # Converting a currency to itself is identity. Handled here rather than by
    # seeding 1.0 rates for every currency against itself, which would be rows
    # that exist only to satisfy a lookup.
    if from == base
      return Result.new(amount_minor: amount_minor, currency_code: base, rate: BigDecimal(1))
    end

    rate = ExchangeRate.effective!(from: from, to: base, on: on)

    Result.new(amount_minor: rate.convert(amount_minor), currency_code: base, rate: rate.rate)
  end
end
