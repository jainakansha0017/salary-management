FactoryBot.define do
  factory :currency do
    code { "USD" }
    name { "US Dollar" }
    symbol { "$" }
    minor_unit { 2 }

    # JPY is the standard counter-example to "money always has two decimals".
    trait :jpy do
      code { "JPY" }
      name { "Japanese Yen" }
      symbol { "¥" }
      minor_unit { 0 }
    end

    trait :gbp do
      code { "GBP" }
      name { "Pound Sterling" }
      symbol { "£" }
    end

    trait :inr do
      code { "INR" }
      name { "Indian Rupee" }
      symbol { "₹" }
    end
  end
end
