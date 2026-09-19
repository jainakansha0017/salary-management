require "rails_helper"

RSpec.describe "GET /api/v1/analytics/breakdown" do
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

  it "answers what each country costs and what it pays, largest first" do
    hire(salary: 100_000, country_code: "GB")
    hire(salary: 140_000, country_code: "GB")
    hire(salary: 60_000, country_code: "PL")

    get "/api/v1/analytics/breakdown", params: { dimension: "country" }

    expect(response).to have_http_status(:ok)
    expect(body["data"]["dimension"]).to eq("country")
    expect(body["data"]["groups"].map { |group| group["key"] }).to eq(%w[GB PL])
    expect(body["data"]["groups"].first).to include("headcount" => 2, "label" => "GB")
    expect(body["data"]["groups"].first["total"]).to include("amount_minor" => 240_000_00)
  end

  it "gives a department its name, so the client does not have to look it up" do
    engineering = create(:department, name: "Engineering")
    hire(salary: 150_000, department: engineering)

    get "/api/v1/analytics/breakdown", params: { dimension: "department" }

    expect(body["data"]["groups"].first).to include("key" => engineering.id, "label" => "Engineering")
  end

  it "sends the quartile spread that shows whether a band still means anything" do
    hire(salary: 80_000, job_level: "L3")
    hire(salary: 90_000, job_level: "L3")

    get "/api/v1/analytics/breakdown", params: { dimension: "job_level" }

    percentiles = body["data"]["groups"].first["percentiles"]
    expect(percentiles.keys).to eq(%w[p25 median p75])
    expect(percentiles["median"]).to include("amount_minor" => 85_000_00, "minor_unit" => 2)
  end

  it "accepts the directory's filters, so a chart can follow the list" do
    hire(salary: 100_000, country_code: "GB", job_level: "L3")
    hire(salary: 400_000, country_code: "GB", job_level: "L5")

    get "/api/v1/analytics/breakdown", params: { dimension: "country", job_level: [ "L3" ] }

    expect(body["data"]["groups"].first["total"]).to include("amount_minor" => 100_000_00)
    expect(body["meta"]["applied"]).to include("dimension" => "country", "job_level" => [ "L3" ])
  end

  # A bad sort key on the directory is ignored, because it is a preference. The
  # dimension is the question, so answering a different one would be worse.
  it "refuses a dimension it does not recognise instead of picking one" do
    get "/api/v1/analytics/breakdown", params: { dimension: "salary" }

    expect(response).to have_http_status(:bad_request)
    expect(body["error"]).to include("code" => "invalid_parameter")
    expect(body["error"]["message"]).to include("country, department, job_level")
  end

  it "refuses a missing dimension rather than guessing at one" do
    get "/api/v1/analytics/breakdown"

    expect(response).to have_http_status(:bad_request)
  end
end
