module Seeds
  # Currencies, countries, departments and the exchange rate history.
  #
  # Rates are effective-dated across several periods rather than a single
  # current value, so that a salary set in 2022 converts at a 2022 rate. Without
  # that, the historical half of the data would all convert at today's rate and
  # the point of ADR-3 would never actually be exercised.
  module ReferenceData
    CURRENCIES = [
      { code: "USD", name: "US Dollar", symbol: "$", minor_unit: 2 },
      { code: "GBP", name: "Pound Sterling", symbol: "£", minor_unit: 2 },
      { code: "EUR", name: "Euro", symbol: "€", minor_unit: 2 },
      { code: "INR", name: "Indian Rupee", symbol: "₹", minor_unit: 2 },
      { code: "JPY", name: "Japanese Yen", symbol: "¥", minor_unit: 0 },
      { code: "SGD", name: "Singapore Dollar", symbol: "S$", minor_unit: 2 },
      { code: "AUD", name: "Australian Dollar", symbol: "A$", minor_unit: 2 },
      { code: "CAD", name: "Canadian Dollar", symbol: "C$", minor_unit: 2 },
      { code: "BRL", name: "Brazilian Real", symbol: "R$", minor_unit: 2 },
      { code: "PLN", name: "Polish Zloty", symbol: "zł", minor_unit: 2 }
    ].freeze

    # Country, its currency, and the share of headcount sitting there.
    COUNTRIES = [
      { code: "US", currency: "USD", weight: 30 },
      { code: "IN", currency: "INR", weight: 22 },
      { code: "GB", currency: "GBP", weight: 12 },
      { code: "DE", currency: "EUR", weight: 8 },
      { code: "PL", currency: "PLN", weight: 7 },
      { code: "BR", currency: "BRL", weight: 6 },
      { code: "CA", currency: "CAD", weight: 5 },
      { code: "AU", currency: "AUD", weight: 4 },
      { code: "SG", currency: "SGD", weight: 3 },
      { code: "JP", currency: "JPY", weight: 3 }
    ].freeze

    DEPARTMENTS = [
      "Engineering", "Data", "Product", "Design", "Sales",
      "Marketing", "Customer Success", "Finance", "People", "Legal"
    ].freeze

    # The first period is deliberately long so that every hire date in the data
    # falls inside a period and no conversion can fail.
    RATE_PERIOD_STARTS = [
      Date.new(2015, 1, 1),
      Date.new(2022, 1, 1),
      Date.new(2023, 1, 1),
      Date.new(2024, 1, 1),
      Date.new(2025, 1, 1),
      Date.new(2026, 1, 1)
    ].freeze

    # Units of USD per one unit of the local currency, one entry per period
    # above. Approximate real-world values — enough to make cross-country
    # comparison meaningful without pretending to be a market data feed.
    RATES_TO_USD = {
      "GBP" => [ 1.37, 1.24, 1.24, 1.27, 1.29, 1.30 ],
      "EUR" => [ 1.18, 1.05, 1.08, 1.09, 1.10, 1.12 ],
      "INR" => [ 0.0135, 0.0126, 0.0121, 0.0120, 0.0117, 0.0115 ],
      "JPY" => [ 0.0091, 0.0076, 0.0071, 0.0066, 0.0064, 0.0063 ],
      "SGD" => [ 0.744, 0.730, 0.748, 0.745, 0.755, 0.760 ],
      "AUD" => [ 0.750, 0.690, 0.665, 0.660, 0.650, 0.655 ],
      "CAD" => [ 0.797, 0.768, 0.741, 0.730, 0.720, 0.725 ],
      "BRL" => [ 0.186, 0.190, 0.202, 0.185, 0.180, 0.178 ],
      "PLN" => [ 0.256, 0.225, 0.238, 0.250, 0.255, 0.258 ]
    }.freeze

    BASE_CURRENCY = "USD".freeze

    def self.load!
      load_currencies!
      load_exchange_rates!
      load_departments!
    end

    def self.load_currencies!
      Currency.insert_all!(CURRENCIES.map { |c| c.merge(created_at: Time.current, updated_at: Time.current) })
    end

    def self.load_exchange_rates!
      rows = RATES_TO_USD.flat_map do |code, rates|
        rates.each_with_index.map do |rate, index|
          {
            from_currency_code: code,
            to_currency_code: BASE_CURRENCY,
            rate: rate,
            effective_from: RATE_PERIOD_STARTS[index],
            # Periods are half-open and consecutive; the last one stays open.
            effective_to: RATE_PERIOD_STARTS[index + 1],
            created_at: Time.current,
            updated_at: Time.current
          }
        end
      end

      ExchangeRate.insert_all!(rows)
    end

    def self.load_departments!
      Department.insert_all!(
        DEPARTMENTS.map { |name| { name: name, created_at: Time.current, updated_at: Time.current } }
      )
    end
  end
end
