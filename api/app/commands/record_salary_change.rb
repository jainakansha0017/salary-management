# Records a new salary for an employee.
#
# This is the only supported way for pay to change. It closes the period on the
# outgoing record and opens a new one, so the previous amount is preserved
# rather than overwritten (ADR-2). No existing amount is ever modified — only a
# period is closed.
class RecordSalaryChange
  class BackdatedChange < StandardError; end

  # Two changes for the same employee landing at the same moment. The loser is
  # told to reload, rather than being shown a Postgres constraint name.
  class ConcurrentChange < StandardError; end

  def self.call(...)
    new(...).call
  end

  def initialize(employee:, amount_minor:, currency_code:, effective_from:, reason:, note: nil)
    @employee = employee
    @amount_minor = amount_minor
    @currency_code = currency_code
    @effective_from = effective_from
    @reason = reason
    @note = note
  end

  def call
    # The whole change is one transaction: closing the old period and opening
    # the new one must either both happen or neither, or the employee is left
    # with no current salary at all.
    Compensation.transaction do
      close_current_period
      create_new_period
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::StatementInvalid => error
    raise unless overlapping_period?(error)

    raise ConcurrentChange,
          "this employee's pay was changed by someone else a moment ago; reload and try again"
  end

  private

  attr_reader :employee, :amount_minor, :currency_code, :effective_from, :reason, :note

  def close_current_period
    # Deliberately not `SELECT ... FOR UPDATE`. A row lock cannot stop a
    # concurrent insert of a row that does not exist yet, which is exactly the
    # race here — measured, both with and without the lock, the loser fails the
    # same way. The guarantee comes from the schema: an exclusion constraint on
    # overlapping periods and a partial unique index allowing one open-ended
    # period per employee. Leaving the lock in place would imply protection it
    # does not give.
    current = employee.compensations.current.first
    return if current.nil?

    if effective_from <= current.effective_from
      raise BackdatedChange,
            "a salary change must take effect after the current salary began on #{current.effective_from}"
    end

    current.update!(effective_to: effective_from)
  end

  def create_new_period
    converted = BaseCurrencyConverter.call(
      amount_minor: amount_minor, from: currency_code, on: effective_from
    )

    employee.compensations.create!(
      amount_minor: amount_minor,
      currency_code: currency_code,
      amount_base_minor: converted.amount_minor,
      base_currency_code: converted.currency_code,
      exchange_rate_used: converted.rate,
      effective_from: effective_from,
      reason: reason,
      note: note
    )
  end

  # Narrow on purpose. Any other StatementInvalid is a bug, and dressing it up
  # as a retryable conflict would hide it.
  def overlapping_period?(error)
    error.is_a?(ActiveRecord::RecordNotUnique) || error.cause.is_a?(PG::ExclusionViolation)
  end
end
