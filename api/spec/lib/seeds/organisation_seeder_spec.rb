require "rails_helper"

RSpec.describe Seeds::OrganisationSeeder do
  # Small but not tiny: enough employees for every country and level to appear,
  # fast enough to stay in the unit suite.
  let(:employee_count) { 120 }
  let(:silent) { StringIO.new }

  def seed(seed_value: described_class::DEFAULT_SEED)
    described_class.new(employee_count: employee_count, seed: seed_value, io: silent).call
  end

  describe "the organisation it produces" do
    before { seed }

    it "creates the requested number of employees" do
      expect(Employee.count).to eq(employee_count)
    end

    it "gives every active employee exactly one current salary" do
      current_counts = Compensation.current.group(:employee_id).count

      Employee.active.find_each do |employee|
        expect(current_counts[employee.id]).to eq(1), "#{employee.employee_number} has no single current salary"
      end
    end

    it "leaves departed employees with no current salary, so payroll cost excludes them" do
      departed = Employee.where.not(ended_on: nil)

      expect(departed).to be_any
      expect(Compensation.current.where(employee: departed)).to be_empty
    end

    it "gives everyone a hire record as the start of their history" do
      Employee.find_each do |employee|
        first = employee.compensations.order(:effective_from).first

        expect(first.reason).to eq("hire")
        expect(first.effective_from).to eq(employee.hired_on)
      end
    end

    it "leaves no gap or overlap between consecutive periods" do
      Compensation.where(employee_id: Employee.limit(25).select(:id))
                  .order(:employee_id, :effective_from)
                  .group_by(&:employee_id)
                  .each_value do |records|
        records.each_cons(2) do |earlier, later|
          expect(earlier.effective_to).to eq(later.effective_from)
        end
      end
    end

    it "only places people in configured countries and pay bands" do
      expect(Employee.distinct.pluck(:country_code)).to all(be_in(Seeds::ReferenceData::COUNTRIES.map { |c| c[:code] }))
      expect(Employee.distinct.pluck(:job_level)).to all(be_in(Seeds::SalaryModel::LEVELS.keys))
    end
  end

  describe "currency conversion" do
    before { seed }

    # The seed inserts rows in bulk rather than going through
    # RecordSalaryChange, so this is the guard against the two drifting apart
    # on the part that matters: the arithmetic.
    it "converts exactly as the write path would" do
      Compensation.limit(50).includes(:employee).find_each do |compensation|
        expected = BaseCurrencyConverter.call(
          amount_minor: compensation.amount_minor,
          from: compensation.currency_code,
          on: compensation.effective_from
        )

        expect(compensation.amount_base_minor).to eq(expected.amount_minor)
        expect(compensation.exchange_rate_used).to eq(expected.rate)
      end
    end

    it "does not treat yen as if it had minor units" do
      yen = Compensation.joins(:employee).where(currency_code: "JPY").first

      # A ¥15m salary is roughly $95k. If the exponent were ignored it would
      # come out near $950, which is the bug this pins.
      expect(yen.amount_base_minor).to be > 20_000_00
    end
  end

  describe "the shape of the data" do
    # A larger organisation, because the interesting properties are statistical.
    # Singapore is 3% of headcount, so at 120 employees it can legitimately be
    # absent — asserting on it there would be brittle rather than meaningful.
    before { described_class.new(employee_count: 1_000, seed: 1, io: silent).call }

    it "fills every country and pay band at a realistic organisation size" do
      expect(Employee.distinct.pluck(:country_code))
        .to match_array(Seeds::ReferenceData::COUNTRIES.map { |c| c[:code] })
      expect(Employee.distinct.pluck(:job_level))
        .to match_array(Seeds::SalaryModel::LEVELS.keys)
    end

    it "pays higher levels more, so comparisons are meaningful" do
      medians = Compensation.current
                            .joins(:employee)
                            .group("employees.job_level")
                            .minimum(:amount_base_minor)

      expect(medians["L7"]).to be > medians["L2"]
    end

    it "produces a right-skewed distribution rather than a uniform one" do
      amounts = Compensation.current.pluck(:amount_base_minor).sort
      median = amounts[amounts.size / 2]
      mean = amounts.sum / amounts.size

      # In a real pay distribution the long tail upwards pulls the mean above
      # the median. A uniform spread would put them level.
      expect(mean).to be > median
    end

    it "includes people paid well below their peer group for the outlier view to find" do
      by_peer_group = Compensation.current
                                  .joins(:employee)
                                  .pluck("employees.country_code", "employees.job_level", :amount_base_minor)
                                  .group_by { |country, level, _| [ country, level ] }

      underpaid = by_peer_group.sum do |_group, rows|
        amounts = rows.map(&:last).sort
        median = amounts[amounts.size / 2]

        amounts.count { |amount| amount < median * 0.8 }
      end

      expect(underpaid).to be_positive
    end
  end
end
