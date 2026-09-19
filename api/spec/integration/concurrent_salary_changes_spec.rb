require "rails_helper"

# Two changes for one employee at the same moment: an HR manager and a
# scheduled review, or one person with the form open in two tabs.
#
# The invariant — one current salary, always — is held by the schema, not by
# the application: an exclusion constraint on overlapping periods and a partial
# unique index allowing one open-ended period per employee. Nothing in a
# single-threaded suite can tell you whether that actually works, so it is
# tested here rather than asserted in a comment.
#
# `SELECT ... FOR UPDATE` was tried and removed. It cannot stop a concurrent
# insert of a row that does not exist yet, and measured both ways the loser
# failed identically.
RSpec.describe "recording two salary changes at the same moment" do
  # Real threads need to see each other's committed work, which the suite's
  # wrapping transaction would hide. Cleanup is manual as a result.
  self.use_transactional_tests = false

  let(:effective_from) { Date.new(2026, 10, 1) }

  after do
    Compensation.delete_all
    Employee.delete_all
    Department.delete_all
    Currency.delete_all
  end

  def record_concurrently(employee, count: 2)
    at_the_line = Queue.new
    go = Queue.new

    threads = Array.new(count) do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          at_the_line << true
          go.pop # Start together, so the two attempts genuinely overlap.

          begin
            RecordSalaryChange.call(
              employee: employee, amount_minor: 99_000_00 + index, currency_code: "USD",
              effective_from: effective_from, reason: :merit_increase
            )
            :recorded
          rescue StandardError => error
            error.class
          end
        end
      end
    end

    count.times { at_the_line.pop }
    count.times { go << true }
    threads.map(&:value)
  end

  it "leaves the employee with exactly one current salary" do
    create(:currency)
    employee = create(:employee)
    create(:compensation, employee: employee, amount_minor: 90_000_00, effective_from: Date.new(2026, 1, 1))

    outcomes = record_concurrently(employee)

    # The failure this guards against is two open-ended periods, which would
    # make payroll cost depend on which row the database happened to return.
    expect(Compensation.current.where(employee: employee).count).to eq(1)
    expect(outcomes.count(:recorded)).to eq(1)
  end

  it "tells the loser it lost, rather than leaking a constraint violation" do
    create(:currency)
    employee = create(:employee)
    create(:compensation, employee: employee, amount_minor: 90_000_00, effective_from: Date.new(2026, 1, 1))

    outcomes = record_concurrently(employee)

    # Without the translation in RecordSalaryChange this is
    # ActiveRecord::StatementInvalid, and the endpoint answers 500 with a
    # Postgres constraint name in it.
    expect(outcomes).to include(RecordSalaryChange::ConcurrentChange)
  end

  it "records the losing attempt as nothing at all, not as a partial write" do
    create(:currency)
    employee = create(:employee)
    original = create(:compensation, employee: employee, amount_minor: 90_000_00, effective_from: Date.new(2026, 1, 1))

    record_concurrently(employee)

    # One closed period and one open one. Three rows would mean a change was
    # half-applied; one would mean the original was closed with no replacement.
    expect(employee.compensations.count).to eq(2)
    expect(original.reload.effective_to).to eq(effective_from)
    expect(employee.compensations.current.first.effective_from).to eq(effective_from)
  end
end
