require "rails_helper"

RSpec.describe "GET /api/v1/analytics/summary" do
  let(:body) { response.parsed_body }
  let!(:usd) { create(:currency) }

  def hire(salary:, **attributes)
    employee = create(:employee, **attributes)
    create(
      :compensation,
      employee: employee, currency: usd, base_currency: usd,
      amount_minor: salary * 100, amount_base_minor: salary * 100,
      effective_from: Date.new(2025, 1, 1)
    )
    employee
  end

  it "answers how much the organisation spends on pay and how it is spread" do
    [ 60_000, 80_000, 100_000, 140_000 ].each { |salary| hire(salary: salary) }

    get "/api/v1/analytics/summary"

    expect(response).to have_http_status(:ok)
    expect(body["data"]).to include("headcount" => 4)
    expect(body["data"]["total"]).to include("amount_minor" => 380_000_00, "currency_code" => "USD")
    expect(body["data"]["percentiles"]["median"]).to include("amount_minor" => 90_000_00)
  end

  # Without the exponent the client has to assume two decimals, which is wrong
  # for JPY and would show ¥15,000,000 as ¥150,000.00 (ADR-6).
  it "sends every figure as minor units with its currency, never as a formatted string" do
    hire(salary: 90_000)

    get "/api/v1/analytics/summary"

    amounts = [ body["data"]["total"], body["data"]["average"], *body["data"]["percentiles"].values ]
    expect(amounts).to all(include("amount_minor", "currency_code", "minor_unit" => 2))
  end

  it "returns a histogram the dashboard can draw without doing arithmetic" do
    [ 41_000, 52_000, 55_000, 88_000 ].each { |salary| hire(salary: salary) }

    get "/api/v1/analytics/summary"

    bands = body["data"]["distribution"]
    expect(bands.sum { |band| band["headcount"] }).to eq(4)
    expect(bands.first).to include("from", "to", "headcount")
  end

  it "applies the directory's filters, so a chart and a list can share parameters" do
    engineering = create(:department, name: "Engineering")
    hire(salary: 100_000, department: engineering)
    hire(salary: 400_000)

    get "/api/v1/analytics/summary", params: { department_id: [ engineering.id ] }

    expect(body["data"]["headcount"]).to eq(1)
    expect(body["data"]["total"]).to include("amount_minor" => 100_000_00)
  end

  it "reports an empty group as zero cost rather than as an error" do
    hire(salary: 90_000)

    get "/api/v1/analytics/summary", params: { country_code: [ "JP" ] }

    expect(response).to have_http_status(:ok)
    expect(body["data"]).to include("headcount" => 0, "average" => nil)
    expect(body["data"]["total"]).to include("amount_minor" => 0)
    expect(body["data"]["distribution"]).to be_empty
  end

  it "echoes the date it answered for, so the client is not guessing" do
    hire(salary: 90_000)

    get "/api/v1/analytics/summary", params: { as_of: "2025-06-30" }

    expect(body["meta"]["applied"]).to include("as_of" => "2025-06-30")
  end
end
