FactoryBot.define do
  factory :compensation do
    employee
    currency { Currency.find_by(code: "USD") || create(:currency) }
    base_currency { currency }

    amount_minor { 120_000_00 }
    amount_base_minor { amount_minor }
    exchange_rate_used { 1 }

    effective_from { 2.years.ago.to_date }
    effective_to { nil }
    reason { :hire }

    trait :closed do
      effective_to { 1.year.ago.to_date }
    end
  end
end
