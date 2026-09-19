require "rails_helper"

RSpec.describe PayrollBreakdownQuery do
  let(:today) { Date.new(2026, 6, 30) }
  let!(:usd) { create(:currency) }

  def hire(salary:, from: Date.new(2025, 1, 1), to: nil, **attributes)
    employee = create(:employee, **attributes)
    create(
      :compensation,
      employee: employee, currency: usd, base_currency: usd,
      amount_minor: salary * 100, amount_base_minor: salary * 100,
      effective_from: from, effective_to: to
    )
    employee
  end

  def rows(dimension, params = {})
    described_class.new(params.merge(dimension: dimension), today: today).call.rows
  end

  describe "grouping by country" do
    before do
      hire(salary: 100_000, country_code: "GB")
      hire(salary: 140_000, country_code: "GB")
      hire(salary: 60_000, country_code: "PL")
    end

    it "reports one row per country the filtered population actually has" do
      expect(rows("country").map(&:key)).to contain_exactly("GB", "PL")
    end

    it "reports each group's cost and spread separately" do
      gb = rows("country").find { |row| row.key == "GB" }

      expect(gb.headcount).to eq(2)
      expect(gb.total_minor).to eq(240_000_00)
      expect(gb.average_minor).to eq(120_000_00)
      expect(gb.percentiles[:median]).to eq(120_000_00)
    end

    # A breakdown is read to find the expensive group, so it should not have to
    # be re-sorted by the reader.
    it "puts the largest cost centre first" do
      expect(rows("country").map(&:key)).to eq(%w[GB PL])
    end

    it "labels a country by its code, which is already what a person reads" do
      expect(rows("country").map(&:label)).to eq(%w[GB PL])
    end
  end

  describe "grouping by department" do
    def staff_three_departments
      engineering = create(:department, name: "Engineering")
      hire(salary: 150_000, department: engineering)
      hire(salary: 90_000, department: create(:department, name: "Sales"))
      hire(salary: 70_000, department: create(:department, name: "Support"))
      engineering
    end

    # Grouping on the name would merge two departments that happen to share one,
    # and would change every historical figure if a department were renamed.
    it "groups on the id and resolves the name for display" do
      engineering = staff_three_departments
      top = rows("department").first

      expect(top.key).to eq(engineering.id)
      expect(top.label).to eq("Engineering")
    end

    # Resolving names one group at a time is the obvious way to write this and
    # the wrong one: at ten departments it is ten extra queries per dashboard.
    it "resolves every name in one query, not one per group", :n_plus_one do
      ignoring_n_plus_one { staff_three_departments }

      expect(rows("department").map(&:label)).to contain_exactly("Engineering", "Sales", "Support")
    end
  end

  describe "grouping by job level" do
    before do
      hire(salary: 80_000, job_level: "L3")
      hire(salary: 90_000, job_level: "L3")
      hire(salary: 160_000, job_level: "L5")
    end

    # Overlapping quartiles between adjacent levels is the signal that a pay
    # band has stopped meaning anything, which is the point of this view.
    it "reports the quartile spread each band is paid across" do
      l3 = rows("job_level").find { |row| row.key == "L3" }

      expect(l3.percentiles.keys).to eq(%i[p25 median p75])
      expect(l3.percentiles[:p25]).to eq(82_500_00)
      expect(l3.percentiles[:p75]).to eq(87_500_00)
    end
  end

  describe "who is counted" do
    it "counts the same population the summary does" do
      hire(salary: 100_000, country_code: "GB")
      hire(salary: 500_000, country_code: "GB", from: Date.new(2024, 1, 1),
           to: Date.new(2026, 3, 1), ended_on: Date.new(2026, 3, 1))

      expect(rows("country").sole.headcount).to eq(1)
    end

    it "applies the directory's filters before grouping" do
      hire(salary: 100_000, country_code: "GB", job_level: "L3")
      hire(salary: 200_000, country_code: "PL", job_level: "L3")
      hire(salary: 400_000, country_code: "GB", job_level: "L5")

      expect(rows("country", job_level: "L3").map(&:key)).to contain_exactly("GB", "PL")
      expect(rows("country", job_level: "L3").first.total_minor).to eq(200_000_00)
    end

    it "returns no groups rather than an empty group when nobody matches" do
      hire(salary: 100_000, country_code: "GB")

      expect(rows("country", country_code: "JP")).to be_empty
    end
  end

  describe "the dimension itself" do
    # Contrast with sort and status, which the directory silently defaults.
    # Those are preferences; this is the question.
    it "refuses one it does not recognise rather than answering a different one" do
      expect { rows("salary") }.to raise_error(described_class::UnknownDimension, /country, department, job_level/)
      expect { rows(nil) }.to raise_error(described_class::UnknownDimension)
    end

    it "refuses a SQL expression, so the group-by cannot be dictated by a caller" do
      expect { rows("employees.email") }.to raise_error(described_class::UnknownDimension)
    end
  end
end
