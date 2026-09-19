require "rails_helper"

RSpec.describe SalaryChangeForm do
  let(:employee) { create(:employee) }

  # Both are reference data rather than subjects. GBP exists but has no rate on
  # file, which is what makes the "cannot convert" case reachable.
  before do
    create(:currency)
    create(:currency, :gbp)
  end

  def form(**overrides)
    described_class.new(
      employee: employee,
      **{
        amount_minor: 99_000_00,
        currency_code: "USD",
        effective_from: "2026-10-01",
        reason: "merit_increase"
      }.merge(overrides)
    )
  end

  describe "a well-formed change" do
    it "records it and exposes the new period" do
      subject = form

      expect(subject.save).to be(true)
      expect(subject.compensation).to be_current
      expect(subject.compensation.amount_minor).to eq(99_000_00)
      expect(subject.compensation.effective_from).to eq(Date.new(2026, 10, 1))
    end

    it "accepts a lowercase currency code rather than rejecting it silently" do
      expect(form(currency_code: "usd").save).to be(true)
    end
  end

  describe "amounts" do
    # The whole point of storing minor units is that money is never a fraction.
    # Casting this to an integer would accept the request and quietly lose 50p.
    it "refuses a fractional amount instead of rounding it" do
      subject = form(amount_minor: "99000.50")

      expect(subject.save).to be(false)
      expect(subject.errors[:amount_minor]).to include("must be a whole number of minor units")
    end

    it "refuses an amount that is not a number at all" do
      expect(form(amount_minor: "lots").save).to be(false)
    end

    it "refuses zero and negative pay" do
      expect(form(amount_minor: 0).save).to be(false)
      expect(form(amount_minor: -100).save).to be(false)
    end

    it "accepts an integer sent as a JSON string, because that is how forms post" do
      expect(form(amount_minor: "9900000").save).to be(true)
    end
  end

  describe "dates" do
    it "refuses a date that does not exist, naming the field" do
      subject = form(effective_from: "2026-02-30")

      expect(subject.save).to be(false)
      expect(subject.errors[:effective_from]).to include("must be a date in YYYY-MM-DD form")
    end

    it "refuses a missing date with the same message, because both are the same problem to fix" do
      subject = form(effective_from: nil)

      expect(subject.save).to be(false)
      expect(subject.errors[:effective_from]).to include("must be a date in YYYY-MM-DD form")
    end
  end

  describe "reasons" do
    it "accepts every reason the domain defines" do
      Compensation::REASONS.each_key do |reason|
        expect(form(reason: reason.to_s, effective_from: "2026-10-01").valid?).to be(true), reason.to_s
      end
    end

    it "refuses an invented reason, and says what the options are" do
      subject = form(reason: "felt_like_it")

      expect(subject.save).to be(false)
      expect(subject.errors[:reason].first).to include("merit_increase")
    end
  end

  describe "currencies" do
    it "refuses a currency the system does not hold" do
      subject = form(currency_code: "ZWL")

      expect(subject.save).to be(false)
      expect(subject.errors[:currency_code]).to include("is not a currency this system holds rates for")
    end

    it "reports a missing exchange rate as a problem with the currency, not as a crash" do
      subject = form(currency_code: "GBP")

      expect(subject.save).to be(false)
      expect(subject.errors[:currency_code]).to be_any
    end
  end

  describe "changes the domain rejects" do
    before do
      create(:compensation, employee: employee, effective_from: Date.new(2026, 1, 1))
    end

    it "reports a backdated change against the date field, so the UI knows where to point" do
      subject = form(effective_from: "2025-06-01")

      expect(subject.save).to be(false)
      expect(subject.errors[:effective_from].first).to include("must take effect after")
    end

    it "does not record anything when it refuses" do
      form(effective_from: "2025-06-01").save

      expect(employee.compensations.count).to eq(1)
    end
  end
end
