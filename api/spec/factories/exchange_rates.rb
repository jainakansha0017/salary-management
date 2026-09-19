FactoryBot.define do
  factory :exchange_rate do
    from_currency { Currency.find_by(code: "GBP") || create(:currency, :gbp) }
    to_currency { Currency.find_by(code: "USD") || create(:currency) }
    rate { "1.25" }
    effective_from { Date.new(2026, 1, 1) }
    effective_to { nil }
  end
end
