require "rails_helper"

RSpec.describe PayrollSummaryQuery do
  let(:today) { Date.new(2026, 6, 30) }
  let!(:usd) { create(:currency) }

  # Salaries are given in whole units for readability; the query works in minor
  # units like everything else.
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

  def summary(params = {})
    described_class.new(params, today: today).call
  end

  describe "the headline figures" do
    before do
      hire(salary: 50_000)
      hire(salary: 70_000)
      hire(salary: 90_000)
      hire(salary: 110_000)
    end

    it "reports the cost of the payroll, not an average of averages" do
      expect(summary.headcount).to eq(4)
      expect(summary.total_minor).to eq(320_000_00)
      expect(summary.average_minor).to eq(80_000_00)
    end

    it "reports the range, so the dashboard can say what it spans" do
      expect(summary.minimum_minor).to eq(50_000_00)
      expect(summary.maximum_minor).to eq(110_000_00)
    end

    # The mean of this group is also 80,000, so a median that merely echoed the
    # mean would pass. The pay below is skewed to keep the two apart.
    it "reports a median that sits between the two middle salaries" do
      hire(salary: 30_000)
      hire(salary: 500_000)

      expect(summary.percentiles[:median]).to eq(80_000_00)
      expect(summary.average_minor).to be > summary.percentiles[:median]
    end

    it "reports the quartiles and tails HR compares bands against" do
      expect(summary.percentiles.keys).to eq(%i[p10 p25 median p75 p90])
      expect(summary.percentiles[:p25]).to eq(65_000_00)
      expect(summary.percentiles[:p75]).to eq(95_000_00)
    end
  end

  describe "who is counted" do
    it "counts the salary in effect on the date, not the newest one" do
      employee = hire(salary: 60_000, from: Date.new(2024, 1, 1), to: Date.new(2026, 1, 1))
      create(
        :compensation,
        employee: employee, currency: usd, base_currency: usd,
        amount_minor: 90_000_00, amount_base_minor: 90_000_00,
        effective_from: Date.new(2026, 1, 1), reason: :merit_increase
      )

      expect(summary.total_minor).to eq(90_000_00)
      expect(summary(as_of: "2025-06-30").total_minor).to eq(60_000_00)
    end

    # A leaver's final period is closed on their leaving date, so this needs no
    # separate rule about employment status.
    it "leaves out someone whose last period closed before the date" do
      hire(salary: 80_000)
      hire(salary: 200_000, from: Date.new(2024, 1, 1), to: Date.new(2026, 3, 1), ended_on: Date.new(2026, 3, 1))

      expect(summary.headcount).to eq(1)
      expect(summary.total_minor).to eq(80_000_00)
    end

    it "narrows to the same population the directory would show" do
      engineering = create(:department, name: "Engineering")
      hire(salary: 100_000, department: engineering, country_code: "GB")
      hire(salary: 200_000, department: engineering, country_code: "PL")
      hire(salary: 400_000, country_code: "GB")

      expect(summary(department_id: engineering.id).headcount).to eq(2)
      expect(summary(country_code: "gb").total_minor).to eq(500_000_00)
      expect(summary(department_id: engineering.id, country_code: "PL").total_minor).to eq(200_000_00)
    end

    it "answers zero rather than nothing when the filters match no one" do
      hire(salary: 80_000)

      result = summary(country_code: "JP")

      expect(result.headcount).to eq(0)
      expect(result.total_minor).to eq(0)
      expect(result.average_minor).to be_nil
      expect(result.bands).to be_empty
    end
  end

  describe "the distribution" do
    before { [ 42_000, 58_000, 61_000, 64_000, 77_000, 95_000 ].each { |salary| hire(salary: salary) } }

    it "places every salary in exactly one band" do
      expect(summary.bands.sum(&:headcount)).to eq(6)
    end

    it "covers the whole range without a gap between bands" do
      bands = summary.bands

      expect(bands.first.from_minor).to be <= 42_000_00
      expect(bands.last.to_minor).to be > 95_000_00
      expect(bands.each_cons(2).all? { |lower, upper| lower.to_minor == upper.from_minor }).to be(true)
    end

    # 17,432 to 24,988 is a correct band and a useless label.
    it "puts the boundaries on round numbers, because a person reads them" do
      widths = summary.bands.map { |band| band.to_minor - band.from_minor }.uniq

      expect(widths.size).to eq(1)
      expect(summary.bands.first.from_minor % widths.first).to eq(0)
    end
  end

  describe "what it reports back" do
    it "echoes the date it used, so an ignored one is visible rather than silent" do
      expect(described_class.new({ as_of: "2025-06-30" }, today: today).applied[:as_of])
        .to eq(Date.new(2025, 6, 30))
      expect(described_class.new({ as_of: "" }, today: today).applied[:as_of]).to eq(today)
    end

    # `Date.parse` reads this as a real date, which would answer a typo with
    # confident figures for a day nobody asked about.
    it "refuses a date that is only date-shaped if you squint" do
      expect(described_class.new({ as_of: "last tuesday" }, today: today).applied[:as_of])
        .to eq(today)
      expect(described_class.new({ as_of: "30/06/2025" }, today: today).applied[:as_of])
        .to eq(today)
    end
  end
end
