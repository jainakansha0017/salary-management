require "rails_helper"

RSpec.describe "GET /api/v1/employees/:id" do
  let!(:usd) { create(:currency) }
  let!(:gbp) { create(:currency, :gbp) }
  let(:employee) { create(:employee, first_name: "Ada", last_name: "Lovelace", country_code: "GB") }
  let(:body) { response.parsed_body }

  def period(from:, to:, amount_minor:, reason:, currency: gbp, rate: "1.25")
    create(
      :compensation,
      employee: employee, currency: currency, base_currency: usd,
      amount_minor: amount_minor,
      amount_base_minor: (amount_minor * BigDecimal(rate)).to_i,
      exchange_rate_used: rate,
      effective_from: from, effective_to: to, reason: reason
    )
  end

  describe "the employee" do
    before do
      period(from: Date.new(2023, 1, 1), to: Date.new(2024, 4, 1), amount_minor: 60_000_00, reason: :hire)
      period(from: Date.new(2024, 4, 1), to: nil, amount_minor: 72_000_00, reason: :promotion)

      get "/api/v1/employees/#{employee.id}"
    end

    it "returns the same identifying fields the directory row uses" do
      expect(response).to have_http_status(:ok)
      expect(body["data"]).to include(
        "id" => employee.id,
        "full_name" => "Ada Lovelace",
        "country_code" => "GB",
        "active" => true
      )
    end

    it "reports current pay, so the header does not have to read the history" do
      expect(body["data"]["current_salary"]["amount"]).to include("amount_minor" => 72_000_00)
    end
  end

  describe "the salary history" do
    let(:history) { body["data"]["salary_history"] }

    before do
      period(from: Date.new(2023, 1, 1), to: Date.new(2024, 4, 1), amount_minor: 60_000_00, reason: :hire)
      period(from: Date.new(2024, 4, 1), to: Date.new(2025, 7, 1), amount_minor: 66_000_00, reason: :merit_increase)
      period(from: Date.new(2025, 7, 1), to: nil, amount_minor: 72_000_00, reason: :promotion)

      get "/api/v1/employees/#{employee.id}"
    end

    it "returns every period, not just the current one" do
      expect(history.size).to eq(3)
    end

    it "orders it newest first, because that is what gets asked about" do
      expect(history.map { |entry| entry["effective_from"] })
        .to eq(%w[2025-07-01 2024-04-01 2023-01-01])
    end

    it "marks exactly one period as current" do
      expect(history.count { |entry| entry["current"] }).to eq(1)
      expect(history.first).to include("current" => true, "effective_to" => nil)
    end

    it "says why each change happened" do
      expect(history.map { |entry| entry["reason"] }).to eq(%w[promotion merit_increase hire])
    end

    it "keeps the rate each amount was converted at, so an old figure can be checked" do
      # A string, not a JSON number: this is an audit trail, and 1.25 is the
      # rate the arithmetic was actually done with.
      expect(history.first["exchange_rate_used"]).to eq("1.25")
      expect(history.first["base_amount"]).to include("currency_code" => "USD", "amount_minor" => 90_000_00)
    end

    it "shows pay in the currency it was agreed in as well as the base one" do
      expect(history.first["amount"]).to eq(
        "amount_minor" => 72_000_00, "currency_code" => "GBP", "minor_unit" => 2
      )
    end
  end

  # A raise can be agreed in advance, which makes "the open-ended period" and
  # "what this person is paid today" two different rows.
  describe "a raise that has been agreed but has not started" do
    before do
      travel_to(Date.new(2026, 9, 19))
      period(from: Date.new(2024, 4, 1), to: Date.new(2027, 1, 1), amount_minor: 72_000_00, reason: :promotion)
      period(from: Date.new(2027, 1, 1), to: nil, amount_minor: 90_000_00, reason: :merit_increase)

      get "/api/v1/employees/#{employee.id}"
    end

    it "reports today's pay as the current salary, not the raise" do
      expect(body["data"]["current_salary"]["amount"]).to include("amount_minor" => 72_000_00)
    end

    it "still lists the agreed raise in the history, so it is not hidden" do
      expect(body["data"]["salary_history"].map { |entry| entry["effective_from"] })
        .to eq(%w[2027-01-01 2024-04-01])
    end

    it "badges the period being paid now, not the one that is merely open-ended" do
      upcoming, in_effect = body["data"]["salary_history"]

      expect(upcoming).to include("current" => false, "effective_to" => nil)
      expect(in_effect).to include("current" => true, "effective_to" => "2027-01-01")
    end
  end

  it "returns a JSON error rather than an HTML page for an employee who does not exist" do
    get "/api/v1/employees/0"

    expect(response).to have_http_status(:not_found)
    expect(body["error"]).to eq("code" => "not_found", "message" => "Employee not found")
  end
end

# There is deliberately no `:n_plus_one` example here, unlike the directory.
# A career's worth of periods resolves to a handful of distinct currencies, and
# Rails' query cache serves the repeats from memory — Prosopite skips cached
# queries, so such a test passes whether or not the preload exists. A guard
# that cannot fail is worse than none, because it reads like a guarantee.
# The preload in the controller still earns its place outside a request cycle,
# where the query cache is not running.
