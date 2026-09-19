require "rails_helper"

RSpec.describe ExchangeRate do
  let!(:usd) { create(:currency) }
  let!(:gbp) { create(:currency, :gbp) }

  describe "#convert" do
    it "multiplies by the rate when both currencies have the same exponent" do
      rate = create(:exchange_rate, from_currency: gbp, to_currency: usd, rate: "1.25")

      # £1,000.00 -> $1,250.00
      expect(rate.convert(100_000)).to eq(125_000)
    end

    it "rescales when converting from a currency with no minor unit" do
      jpy = create(:currency, :jpy)
      rate = create(:exchange_rate, from_currency: jpy, to_currency: usd, rate: "0.0064")

      # ¥1,000,000 (stored as 1_000_000, no minor unit) -> $6,400.00 (640_000 cents).
      # Without rescaling this would silently return 6_400 — a $6,394 error.
      expect(rate.convert(1_000_000)).to eq(640_000)
    end

    it "rescales when converting to a currency with no minor unit" do
      jpy = create(:currency, :jpy)
      rate = create(:exchange_rate, from_currency: usd, to_currency: jpy, rate: "156.25")

      # $1,000.00 (100_000 cents) -> ¥156,250
      expect(rate.convert(100_000)).to eq(156_250)
    end

    it "rounds to a whole minor unit rather than leaving a fraction" do
      rate = create(:exchange_rate, from_currency: gbp, to_currency: usd, rate: "1.23456789")

      expect(rate.convert(100_000)).to eq(123_457)
    end
  end

  describe ".effective!" do
    it "returns the rate whose period covers the date" do
      old = create(:exchange_rate, from_currency: gbp, to_currency: usd, rate: "1.10",
                                   effective_from: Date.new(2025, 1, 1), effective_to: Date.new(2026, 1, 1))
      current = create(:exchange_rate, from_currency: gbp, to_currency: usd, rate: "1.25",
                                       effective_from: Date.new(2026, 1, 1), effective_to: nil)

      expect(described_class.effective!(from: "GBP", to: "USD", on: Date.new(2025, 6, 1))).to eq(old)
      expect(described_class.effective!(from: "GBP", to: "USD", on: Date.new(2026, 6, 1))).to eq(current)
    end

    it "treats the period as half-open, so the end date belongs to the next rate" do
      create(:exchange_rate, from_currency: gbp, to_currency: usd, rate: "1.10",
                             effective_from: Date.new(2025, 1, 1), effective_to: Date.new(2026, 1, 1))
      current = create(:exchange_rate, from_currency: gbp, to_currency: usd, rate: "1.25",
                                       effective_from: Date.new(2026, 1, 1))

      expect(described_class.effective!(from: "GBP", to: "USD", on: Date.new(2026, 1, 1))).to eq(current)
    end

    it "raises rather than returning nil when no rate covers the date" do
      create(:exchange_rate, from_currency: gbp, to_currency: usd, effective_from: Date.new(2026, 1, 1))

      expect { described_class.effective!(from: "GBP", to: "USD", on: Date.new(2025, 1, 1)) }
        .to raise_error(described_class::NotFound, /No exchange rate from GBP to USD/)
    end
  end

  describe "database constraints" do
    it "refuses two rates for the same pair covering the same day" do
      create(:exchange_rate, from_currency: gbp, to_currency: usd,
                             effective_from: Date.new(2026, 1, 1), effective_to: Date.new(2026, 6, 1))

      overlapping = build(:exchange_rate, from_currency: gbp, to_currency: usd,
                                          effective_from: Date.new(2026, 3, 1), effective_to: nil)

      expect { overlapping.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /exchange_rates_no_overlapping_periods/)
    end

    it "allows consecutive periods that meet exactly" do
      create(:exchange_rate, from_currency: gbp, to_currency: usd,
                             effective_from: Date.new(2026, 1, 1), effective_to: Date.new(2026, 6, 1))

      consecutive = build(:exchange_rate, from_currency: gbp, to_currency: usd,
                                          effective_from: Date.new(2026, 6, 1), effective_to: nil)

      expect { consecutive.save! }.not_to raise_error
    end

    it "rejects a non-positive rate" do
      invalid = build(:exchange_rate, from_currency: gbp, to_currency: usd, rate: 0)

      expect { invalid.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /exchange_rates_rate_positive/)
    end
  end
end
