module Seeds
  # Builds an organisation of a given size, with salary history.
  #
  # Rows are inserted in bulk rather than through RecordSalaryChange. That
  # command exists to protect a *user* action — closing one period and opening
  # another safely — and running it 35,000 times would take minutes to produce
  # data whose shape is already known up front. The conversion arithmetic is
  # still shared, because the amounts here go through ExchangeRate#convert, so
  # the seed cannot drift from the write path on the part that matters.
  class OrganisationSeeder
    DEFAULT_SEED = 20_260_919
    BATCH_SIZE = 1_000

    # Roughly one in twenty people has left, so that "active" means something
    # and payroll cost is not simply a count of every row.
    DEPARTURE_RATE = 0.05

    # A small number of people are paid well below their peer group. Without
    # these the outlier view would correctly report nothing, which makes for a
    # truthful but dull demonstration.
    UNDERPAID_RATE = 0.015
    UNDERPAID_FACTOR = (0.62..0.78).freeze

    EARLIEST_HIRE = Date.new(2015, 1, 1)

    def initialize(employee_count:, seed: DEFAULT_SEED, io: $stdout)
      @employee_count = employee_count
      @rng = Random.new(seed)
      @io = io
      @today = Date.current
    end

    def call
      ReferenceData.load!
      load_lookups

      profiles = build_profiles
      insert_employees(profiles)
      insert_compensations(profiles)

      report
    end

    private

    attr_reader :employee_count, :rng, :io, :today

    Profile = Struct.new(
      :employee_number, :first_name, :last_name, :email, :country_code, :currency_code,
      :department_id, :department_name, :job_level, :job_title, :hired_on, :ended_on,
      :target_usd, :employee_id,
      keyword_init: true
    )

    def load_lookups
      @department_ids = Department.pluck(:name, :id).to_h
      @currencies = Currency.all.index_by(&:code)

      # Every rate, in memory, indexed by currency. Resolving a rate per
      # compensation row would otherwise be 35,000 queries.
      @rates = ExchangeRate.all.to_a.each do |rate|
        rate.association(:from_currency).target = @currencies[rate.from_currency_code]
        rate.association(:to_currency).target = @currencies[rate.to_currency_code]
      end
      @rates_by_currency = @rates.group_by(&:from_currency_code)
    end

    def build_profiles
      country_weights = ReferenceData::COUNTRIES.map { |c| [ c, c[:weight] ] }
      level_weights = SalaryModel::LEVELS.map { |level, data| [ level, data[:weight] ] }

      Array.new(employee_count) do |index|
        country = SalaryModel.weighted_pick(rng, country_weights)
        level = SalaryModel.weighted_pick(rng, level_weights)
        department = ReferenceData::DEPARTMENTS.sample(random: rng)
        first_name, last_name = NamePool.sample(country: country[:code], rng: rng)
        hired_on = random_hire_date

        Profile.new(
          employee_number: format("ACME-%05d", index + 1),
          first_name: first_name,
          last_name: last_name,
          # The employee number guarantees uniqueness without needing to retry
          # on collisions between two people with the same name.
          email: "#{first_name}.#{last_name}.#{index + 1}@acme.example".downcase,
          country_code: country[:code],
          currency_code: country[:currency],
          department_id: @department_ids.fetch(department),
          department_name: department,
          job_level: level,
          job_title: SalaryModel.title(level: level, department: department),
          hired_on: hired_on,
          ended_on: random_departure_date(hired_on),
          target_usd: target_for(level, department, country[:code])
        )
      end
    end

    def target_for(level, department, country)
      target = SalaryModel.target_usd(level: level, department: department, country: country, rng: rng)
      target *= rng.rand(UNDERPAID_FACTOR) if rng.rand < UNDERPAID_RATE
      target
    end

    # Skewed towards recent dates, because a growing company hires more people
    # each year than it did the year before.
    def random_hire_date
      span = (today - 30 - EARLIEST_HIRE).to_i
      today - 30 - (span * (rng.rand**1.7)).round
    end

    def random_departure_date(hired_on)
      return nil unless rng.rand < DEPARTURE_RATE

      earliest = hired_on + 180
      return nil if earliest >= today

      earliest + rng.rand((today - earliest).to_i)
    end

    def insert_employees(profiles)
      timestamps = { created_at: Time.current, updated_at: Time.current }

      profiles.each_slice(BATCH_SIZE) do |batch|
        Employee.insert_all!(batch.map { |p| employee_row(p).merge(timestamps) })
      end

      ids = Employee.pluck(:employee_number, :id).to_h
      profiles.each { |p| p.employee_id = ids.fetch(p.employee_number) }
    end

    def employee_row(profile)
      {
        employee_number: profile.employee_number,
        first_name: profile.first_name,
        last_name: profile.last_name,
        email: profile.email,
        country_code: profile.country_code,
        department_id: profile.department_id,
        job_title: profile.job_title,
        job_level: profile.job_level,
        hired_on: profile.hired_on,
        ended_on: profile.ended_on
      }
    end

    def insert_compensations(profiles)
      profiles.each_slice(BATCH_SIZE) do |batch|
        rows = batch.flat_map { |profile| compensation_rows(profile) }
        Compensation.insert_all!(rows)
      end
    end

    # Works backwards from the intended current salary through each past
    # review, so the present-day distribution is exactly the one the salary
    # model describes, and history is consistent with it.
    def compensation_rows(profile)
      review_dates = review_dates_for(profile)

      amount = profile.target_usd
      changes = []

      review_dates.reverse_each do |date|
        promotion = rng.rand < 0.2
        increase = promotion ? rng.rand(0.12..0.20) : rng.rand(0.03..0.08)

        changes.unshift([ date, amount, promotion ? "promotion" : "merit_increase" ])
        amount /= (1 + increase)
      end

      changes.unshift([ profile.hired_on, amount, "hire" ])

      build_rows(profile, changes)
    end

    def review_dates_for(profile)
      last_day = profile.ended_on || today
      dates = []
      date = profile.hired_on

      loop do
        # Reviews land somewhere between eleven and eighteen months apart
        # rather than on a fixed anniversary.
        date += rng.rand(330..560)
        break if date > last_day - 15

        dates << date
      end

      dates
    end

    def build_rows(profile, changes)
      timestamps = { created_at: Time.current, updated_at: Time.current }

      changes.each_with_index.map do |(effective_from, amount_usd, reason), index|
        next_change = changes[index + 1]

        # The final period closes on the leaving date for departed employees,
        # so they correctly have no current salary at all.
        effective_to = next_change ? next_change.first : profile.ended_on

        compensation_row(profile, amount_usd, effective_from, effective_to, reason).merge(timestamps)
      end
    end

    def compensation_row(profile, amount_usd, effective_from, effective_to, reason)
      currency = @currencies.fetch(profile.currency_code)
      rate = rate_for(profile.currency_code, effective_from)

      amount_minor = local_minor_units(amount_usd, currency, rate)
      converted = rate ? rate.convert(amount_minor) : amount_minor

      {
        employee_id: profile.employee_id,
        amount_minor: amount_minor,
        currency_code: profile.currency_code,
        amount_base_minor: converted,
        base_currency_code: ReferenceData::BASE_CURRENCY,
        exchange_rate_used: rate ? rate.rate : 1,
        effective_from: effective_from,
        effective_to: effective_to,
        reason: reason
      }
    end

    # Pay is set in the local currency, so the USD target is translated into
    # local money first and rounded to something a payroll system would
    # actually hold — not a fraction of a cent.
    def local_minor_units(amount_usd, currency, rate)
      local_major = rate ? amount_usd / rate.rate.to_f : amount_usd
      rounded = round_sensibly(local_major)

      (BigDecimal(rounded.to_s) * currency.subunit_factor).to_i
    end

    # Salaries are negotiated in round numbers. Rounding to the nearest 500 in
    # low-denomination currencies and the nearest 100 elsewhere avoids a
    # directory full of values like 92,431.77.
    def round_sensibly(amount)
      step = amount > 1_000_000 ? 10_000 : 100

      (amount / step).round * step
    end

    def rate_for(currency_code, date)
      return nil if currency_code == ReferenceData::BASE_CURRENCY

      @rates_by_currency.fetch(currency_code).find do |rate|
        rate.effective_from <= date && (rate.effective_to.nil? || rate.effective_to > date)
      end
    end

    def report
      io.puts "  employees:     #{Employee.count} (#{Employee.active.count} active)"
      io.puts "  compensations: #{Compensation.count}"
      io.puts "  departments:   #{Department.count}"
      io.puts "  currencies:    #{Currency.count}"
    end
  end
end
