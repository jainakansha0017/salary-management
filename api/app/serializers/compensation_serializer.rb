# One period in someone's salary history.
#
# The deliberate omission is the change from the previous period. The client
# already has both adjacent rows, so a server-computed delta would be a third
# number that can disagree with the two it was derived from — and expressing it
# would mean either a float or a percentage that is meaningless across a
# currency change.
class CompensationSerializer
  def initialize(compensation)
    @compensation = compensation
  end

  def as_json
    {
      id: compensation.id,
      amount: MoneySerializer.call(
        amount_minor: compensation.amount_minor,
        currency: compensation.currency
      ),
      base_amount: MoneySerializer.call(
        amount_minor: compensation.amount_base_minor,
        currency: compensation.base_currency
      ),
      # A string, not a number: this is the rate the conversion was actually
      # made at, and it is the audit trail for a figure someone may query years
      # from now. Rounding it into a double would make it unverifiable.
      exchange_rate_used: compensation.exchange_rate_used.to_s,
      effective_from: compensation.effective_from,
      effective_to: compensation.effective_to,
      current: compensation.current?,
      reason: compensation.reason,
      note: compensation.note
    }
  end

  private

  attr_reader :compensation
end
