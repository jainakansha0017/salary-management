require "rails_helper"

RSpec.describe Compensation do
  let!(:usd) { create(:currency) }
  let(:employee) { create(:employee) }

  describe "database constraints" do
    it "refuses to let an employee be on two salaries at once" do
      create(:compensation, employee: employee,
                            effective_from: Date.new(2025, 1, 1), effective_to: Date.new(2026, 1, 1))

      overlapping = build(:compensation, employee: employee,
                                         effective_from: Date.new(2025, 6, 1), effective_to: nil)

      expect { overlapping.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /compensations_no_overlapping_periods/)
    end

    it "refuses a second open-ended record for the same employee" do
      create(:compensation, employee: employee, effective_from: Date.new(2025, 1, 1))

      second = build(:compensation, employee: employee, effective_from: Date.new(2026, 1, 1))

      expect { second.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "allows consecutive periods that meet exactly" do
      create(:compensation, employee: employee,
                            effective_from: Date.new(2025, 1, 1), effective_to: Date.new(2026, 1, 1))

      consecutive = build(:compensation, employee: employee, effective_from: Date.new(2026, 1, 1))

      expect { consecutive.save! }.not_to raise_error
    end

    it "allows two different employees to hold overlapping periods" do
      other = create(:employee)
      create(:compensation, employee: employee, effective_from: Date.new(2025, 1, 1))

      expect { create(:compensation, employee: other, effective_from: Date.new(2025, 1, 1)) }
        .not_to raise_error
    end

    it "rejects a salary of zero" do
      invalid = build(:compensation, employee: employee, amount_minor: 0)

      expect { invalid.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /compensations_amount_positive/)
    end
  end

  describe "validations" do
    it "rejects an unknown reason as invalid rather than raising" do
      record = build(:compensation, reason: "something_else")

      expect(record).not_to be_valid
      expect(record.errors[:reason]).to be_present
    end

    it "accepts every documented reason" do
      described_class::REASONS.each_key do |reason|
        expect(build(:compensation, reason: reason)).to be_valid
      end
    end

    it "rejects a period that ends before it starts" do
      record = build(:compensation, effective_from: Date.new(2026, 1, 1), effective_to: Date.new(2025, 1, 1))

      expect(record).not_to be_valid
      expect(record.errors[:effective_to]).to include("must be after the start of the period")
    end
  end

  describe ".effective_on" do
    it "finds the salary in force on a given date" do
      first = create(:compensation, employee: employee, amount_minor: 100_000_00,
                                    effective_from: Date.new(2025, 1, 1), effective_to: Date.new(2026, 1, 1))
      second = create(:compensation, employee: employee, amount_minor: 110_000_00,
                                     effective_from: Date.new(2026, 1, 1))

      expect(employee.compensations.effective_on(Date.new(2025, 7, 1))).to contain_exactly(first)
      expect(employee.compensations.effective_on(Date.new(2026, 7, 1))).to contain_exactly(second)
    end
  end

  describe "#amount" do
    it "renders minor units using the currency's exponent" do
      record = build(:compensation, currency: usd, amount_minor: 120_000_00)

      expect(record.amount).to eq(BigDecimal("120000"))
    end

    it "does not divide by 100 for a currency with no minor unit" do
      jpy = create(:currency, :jpy)
      record = build(:compensation, currency: jpy, amount_minor: 8_000_000)

      expect(record.amount).to eq(BigDecimal("8000000"))
    end
  end

  describe "#in_effect_on?" do
    # Half-open, matching the scope: effective on the start date, no longer
    # effective on the end date, so two adjacent periods never both claim a day.
    it "covers the start of the period but not its end" do
      record = build(:compensation, effective_from: Date.new(2026, 1, 1), effective_to: Date.new(2027, 1, 1))

      expect(record).to be_in_effect_on(Date.new(2026, 1, 1))
      expect(record).to be_in_effect_on(Date.new(2026, 12, 31))
      expect(record).not_to be_in_effect_on(Date.new(2027, 1, 1))
      expect(record).not_to be_in_effect_on(Date.new(2025, 12, 31))
    end

    it "is not yet in effect for an open-ended period that starts later" do
      record = build(:compensation, effective_from: Date.new(2027, 1, 1), effective_to: nil)

      expect(record).not_to be_in_effect_on(Date.new(2026, 9, 19))
    end
  end

  describe "Employee#effective_compensation" do
    before { travel_to(Date.new(2026, 6, 30)) }

    it "returns the period covering today, not simply the latest one" do
      create(:compensation, employee: employee, amount_minor: 100_000_00,
                            effective_from: Date.new(2025, 1, 1), effective_to: Date.new(2026, 1, 1))
      in_effect = create(:compensation, employee: employee, amount_minor: 110_000_00,
                                        effective_from: Date.new(2026, 1, 1), effective_to: Date.new(2027, 1, 1))
      create(:compensation, employee: employee, amount_minor: 130_000_00,
                            effective_from: Date.new(2027, 1, 1))

      expect(employee.reload.effective_compensation).to eq(in_effect)
    end
  end
end
