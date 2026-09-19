# Records a new salary for an employee.
#
# This is the only supported way for pay to change. It closes the period on the
# outgoing record and opens a new one, so the previous amount is preserved
# rather than overwritten (ADR-2). No existing amount is ever modified — only a
# period is closed.
class RecordSalaryChange
  class BackdatedChange < StandardError; end

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
  end

  private

  attr_reader :employee, :amount_minor, :currency_code, :effective_from, :reason, :note

  def close_current_period
    current = employee.compensations.current.lock.first
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
end
