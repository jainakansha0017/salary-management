require "rails_helper"

RSpec.describe "GET /api/v1/employees" do
  let!(:usd) { create(:currency) }
  let!(:jpy) { create(:currency, :jpy) }
  let(:body) { response.parsed_body }

  def hire(currency: usd, amount_minor: 120_000_00, base_minor: 120_000_00, **attributes)
    employee = create(:employee, **attributes)
    create(
      :compensation,
      employee: employee, currency: currency, base_currency: usd,
      amount_minor: amount_minor, amount_base_minor: base_minor
    )
    employee
  end

  it "returns a page of employees with the data the directory renders" do
    hire(first_name: "Anna", last_name: "Kowalski", country_code: "PL", job_level: "L5")

    get "/api/v1/employees"

    expect(response).to have_http_status(:ok)
    expect(body["data"].first).to include(
      "full_name" => "Anna Kowalski",
      "country_code" => "PL",
      "job_level" => "L5",
      "active" => true
    )
  end

  it "reports pagination totals, so the UI can render page controls" do
    3.times { hire }

    get "/api/v1/employees", params: { page_size: 2 }

    expect(body["meta"]).to include("page" => 1, "page_size" => 2, "total_count" => 3, "total_pages" => 2)
  end

  it "echoes back how it interpreted the request" do
    get "/api/v1/employees", params: { q: "kowal", sort: "nonsense" }

    # The client asked for a sort that does not exist; saying so is better than
    # silently returning a differently ordered list.
    expect(body["meta"]["applied"]).to include("search" => "kowal", "sort" => "name")
  end

  it "sends money as minor units with its scale, never as a decimal number" do
    hire(currency: jpy, amount_minor: 15_000_000, base_minor: 95_000_00)

    get "/api/v1/employees"

    salary = body["data"].first["current_salary"]
    expect(salary["amount"]).to eq("amount_minor" => 15_000_000, "currency_code" => "JPY", "minor_unit" => 0)
    expect(salary["base_amount"]).to eq("amount_minor" => 95_000_00, "currency_code" => "USD", "minor_unit" => 2)
  end

  it "returns null pay for someone who has left rather than inventing a zero" do
    employee = create(:employee, :departed)
    create(:compensation, :closed, employee: employee)

    get "/api/v1/employees", params: { status: "departed" }

    expect(body["data"].first["current_salary"]).to be_nil
  end

  it "loads a page of many employees in the same number of queries as a page of one", :n_plus_one do
    ignoring_n_plus_one { 25.times { hire } }

    get "/api/v1/employees", params: { page_size: 25 }

    expect(body["data"].size).to eq(25)
  end
end
