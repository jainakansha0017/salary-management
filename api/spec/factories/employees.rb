FactoryBot.define do
  factory :employee do
    department

    sequence(:employee_number) { |n| format("ACME-%05d", n) }
    sequence(:email) { |n| "employee#{n}@acme.example" }
    first_name { "Ada" }
    last_name { "Lovelace" }
    country_code { "GB" }
    job_title { "Software Engineer" }
    job_level { "L3" }
    hired_on { 3.years.ago.to_date }
    ended_on { nil }

    trait :departed do
      ended_on { 1.month.ago.to_date }
    end
  end
end
