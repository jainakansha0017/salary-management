require "rails_helper"

RSpec.describe EmployeeDirectoryQuery do
  let(:today) { Date.new(2026, 6, 30) }
  let!(:usd) { create(:currency) }

  def hire(last_name: "Zeta", first_name: "Ada", salary_minor: 100_000_00, **attributes)
    employee = create(:employee, first_name: first_name, last_name: last_name, **attributes)
    create(
      :compensation,
      employee: employee, currency: usd, base_currency: usd,
      amount_minor: salary_minor, amount_base_minor: salary_minor
    )
    employee
  end

  def results(params = {})
    described_class.new(params, today: today).call.records.to_a
  end

  describe "pagination" do
    before { 5.times { |n| hire(last_name: format("Name%02d", n)) } }

    it "returns only the requested page" do
      page = described_class.new({ page: 2, page_size: 2 }, today: today).call

      expect(page.records.size).to eq(2)
      expect(page.page).to eq(2)
    end

    it "reports the full size of the result set, not the size of the page" do
      page = described_class.new({ page_size: 2 }, today: today).call

      expect(page.total_count).to eq(5)
      expect(page.total_pages).to eq(3)
    end

    it "caps the page size, so a request cannot ask the server to load everything" do
      page = described_class.new({ page_size: 5_000 }, today: today).call

      expect(page.page_size).to eq(described_class::MAX_PAGE_SIZE)
    end

    it "falls back to the first page when the page number is nonsense" do
      expect(described_class.new({ page: "-3" }, today: today).call.page).to eq(1)
      expect(described_class.new({ page: "banana" }, today: today).call.page).to eq(1)
    end

    it "reports a single empty page rather than zero pages when nothing matches" do
      page = described_class.new({ q: "nobody" }, today: today).call

      expect(page.total_count).to eq(0)
      expect(page.total_pages).to eq(1)
    end
  end

  describe "ordering" do
    it "sorts by surname then forename by default" do
      hire(last_name: "Brown", first_name: "Zoe")
      hire(last_name: "Adams", first_name: "Bob")
      hire(last_name: "Adams", first_name: "Alice")

      expect(results.map(&:full_name)).to eq([ "Alice Adams", "Bob Adams", "Zoe Brown" ])
    end

    it "sorts by pay in the base currency, highest first" do
      low = hire(last_name: "Low", salary_minor: 50_000_00)
      high = hire(last_name: "High", salary_minor: 200_000_00)

      expect(results(sort: "salary")).to eq([ high, low ])
    end

    it "puts employees with no current salary last rather than first" do
      paid = hire(last_name: "Paid")
      unpaid = create(:employee, last_name: "Unpaid")

      expect(results(sort: "salary", status: "all")).to eq([ paid, unpaid ])
    end

    # Ten people on the same band earn the same amount, so without a
    # tie-breaker the database may order them differently for each OFFSET,
    # which shows some of them twice and hides others entirely.
    it "pages through tied values without repeating or dropping anyone" do
      10.times { |n| hire(last_name: format("Tied%02d", n), salary_minor: 90_000_00) }

      seen = (1..5).flat_map do |number|
        described_class.new({ sort: "salary", page: number, page_size: 2 }, today: today).call.records.map(&:id)
      end

      expect(seen.uniq.size).to eq(10)
    end

    it "ignores a sort column that is not on the allow-list" do
      # The sort key arrives from a query string and is interpolated into
      # ORDER BY, so anything outside SORTS has to be dropped on the floor.
      employee = hire(last_name: "Adams")

      expect(results(sort: "employees.email; DROP TABLE employees")).to eq([ employee ])
      expect(Employee.count).to eq(1)
    end

    it "honours an explicit direction" do
      first = hire(last_name: "Adams")
      last = hire(last_name: "Zeta")

      expect(results(sort: "name", direction: "desc")).to eq([ last, first ])
    end
  end

  describe "filtering" do
    it "narrows to the selected countries" do
      british = hire(country_code: "GB")
      indian = hire(country_code: "IN")
      hire(country_code: "JP")

      expect(results(country_code: %w[GB IN])).to contain_exactly(british, indian)
    end

    it "narrows to a department" do
      engineering = create(:department, name: "Engineering")
      engineer = hire(department: engineering)
      hire

      expect(results(department_id: [ engineering.id ])).to contain_exactly(engineer)
    end

    it "narrows to a pay band" do
      senior = hire(job_level: "L6")
      hire(job_level: "L2")

      expect(results(job_level: [ "L6" ])).to contain_exactly(senior)
    end

    it "combines filters with search" do
      match = hire(last_name: "Kowalski", country_code: "PL")
      hire(last_name: "Kowalski", country_code: "US")

      expect(results(q: "kowal", country_code: [ "PL" ])).to contain_exactly(match)
    end
  end

  describe "status" do
    let!(:current) { hire(last_name: "Current") }
    let!(:departed) { hire(last_name: "Departed", ended_on: today - 1) }
    let!(:future) { hire(last_name: "Future", hired_on: today + 30) }

    it "shows only current employees by default, because that is the working view" do
      expect(results).to contain_exactly(current)
    end

    it "can show only people who have left" do
      expect(results(status: "departed")).to contain_exactly(departed)
    end

    it "can show everyone, including someone whose start date is still ahead" do
      expect(results(status: "all")).to contain_exactly(current, departed, future)
    end

    it "treats an unrecognised status as the default rather than as no filter" do
      expect(results(status: "everyone")).to contain_exactly(current)
    end
  end

  describe "loading" do
    it "loads a page in the same number of queries regardless of its size", :n_plus_one do
      ignoring_n_plus_one { 25.times { |n| hire(last_name: format("Name%02d", n)) } }

      records = described_class.new({ page_size: 25 }, today: today).call.records

      # Touching everything the directory renders is the assertion: the `:n_plus_one`
      # tag fails the example if any of it triggers a query per row.
      salaries = records.map do |employee|
        [ employee.department.name, employee.current_compensation.currency.code,
          employee.current_compensation.base_currency.code ]
      end

      expect(salaries.size).to eq(25)
    end
  end
end
