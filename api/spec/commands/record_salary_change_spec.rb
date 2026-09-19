require "rails_helper"

RSpec.describe RecordSalaryChange do
  let!(:usd) { create(:currency) }
  let!(:gbp) { create(:currency, :gbp) }
  let(:employee) { create(:employee) }

  describe "recording a first salary" do
    it "opens an open-ended period" do
      result = described_class.call(
        employee: employee, amount_minor: 90_000_00, currency_code: "USD",
        effective_from: Date.new(2025, 1, 1), reason: :hire
      )

      expect(result).to be_current
      expect(result.amount_minor).to eq(90_000_00)
      expect(result.effective_to).to be_nil
    end
  end

  describe "recording a raise" do
    let!(:original) do
      create(:compensation, employee: employee, amount_minor: 90_000_00,
                            effective_from: Date.new(2025, 1, 1))
    end

    it "preserves the previous amount rather than overwriting it" do
      described_class.call(
        employee: employee, amount_minor: 99_000_00, currency_code: "USD",
        effective_from: Date.new(2026, 1, 1), reason: :merit_increase
      )

      expect(original.reload.amount_minor).to eq(90_000_00)
    end

    it "closes the previous period on the day the new one starts" do
      described_class.call(
        employee: employee, amount_minor: 99_000_00, currency_code: "USD",
        effective_from: Date.new(2026, 1, 1), reason: :merit_increase
      )

      expect(original.reload.effective_to).to eq(Date.new(2026, 1, 1))
    end

    it "leaves the employee with exactly one current salary" do
      described_class.call(
        employee: employee, amount_minor: 99_000_00, currency_code: "USD",
        effective_from: Date.new(2026, 1, 1), reason: :merit_increase
      )

      expect(employee.compensations.current.count).to eq(1)
      expect(employee.reload.current_compensation.amount_minor).to eq(99_000_00)
    end

    it "keeps the full history readable" do
      described_class.call(
        employee: employee, amount_minor: 99_000_00, currency_code: "USD",
        effective_from: Date.new(2026, 1, 1), reason: :merit_increase
      )

      expect(employee.compensations.newest_first.map(&:amount_minor)).to eq([ 99_000_00, 90_000_00 ])
    end
  end

  describe "currency conversion" do
    it "converts to the base currency at the rate effective on the change date" do
      create(:exchange_rate, from_currency: gbp, to_currency: usd, rate: "1.20",
                             effective_from: Date.new(2025, 1, 1), effective_to: Date.new(2026, 1, 1))
      create(:exchange_rate, from_currency: gbp, to_currency: usd, rate: "1.30",
                             effective_from: Date.new(2026, 1, 1))

      result = described_class.call(
        employee: employee, amount_minor: 50_000_00, currency_code: "GBP",
        effective_from: Date.new(2025, 6, 1), reason: :hire
      )

      # Deliberately the older rate: the change happened while 1.20 was in force.
      expect(result.exchange_rate_used).to eq(BigDecimal("1.20"))
      expect(result.amount_base_minor).to eq(60_000_00)
    end

    it "records an identity rate when pay is already in the base currency" do
      result = described_class.call(
        employee: employee, amount_minor: 90_000_00, currency_code: "USD",
        effective_from: Date.new(2025, 1, 1), reason: :hire
      )

      expect(result.amount_base_minor).to eq(90_000_00)
      expect(result.exchange_rate_used).to eq(1)
    end

    it "refuses to record pay it cannot convert" do
      expect {
        described_class.call(
          employee: employee, amount_minor: 50_000_00, currency_code: "GBP",
          effective_from: Date.new(2025, 6, 1), reason: :hire
        )
      }.to raise_error(ExchangeRate::NotFound)
    end
  end

  describe "invalid changes" do
    before do
      create(:compensation, employee: employee, effective_from: Date.new(2026, 1, 1))
    end

    it "rejects a change dated before the current salary began" do
      expect {
        described_class.call(
          employee: employee, amount_minor: 99_000_00, currency_code: "USD",
          effective_from: Date.new(2025, 6, 1), reason: :correction
        )
      }.to raise_error(described_class::BackdatedChange)
    end

    it "rejects a change dated on the day the current salary began" do
      expect {
        described_class.call(
          employee: employee, amount_minor: 99_000_00, currency_code: "USD",
          effective_from: Date.new(2026, 1, 1), reason: :correction
        )
      }.to raise_error(described_class::BackdatedChange)
    end

    it "leaves the existing salary untouched when the change is rejected" do
      expect {
        described_class.call(
          employee: employee, amount_minor: 99_000_00, currency_code: "GBP",
          effective_from: Date.new(2026, 6, 1), reason: :correction
        )
      }.to raise_error(ExchangeRate::NotFound)

      # The rollback matters: a failure part-way through must not leave the
      # employee with a closed period and no replacement.
      expect(employee.compensations.current.count).to eq(1)
      expect(employee.reload.current_compensation.effective_to).to be_nil
    end
  end
end
