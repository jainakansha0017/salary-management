# The boundary between a JSON request and RecordSalaryChange.
#
# The command takes typed arguments and enforces domain rules. Everything
# arriving over HTTP is a string, and some of those strings are not the thing
# they claim to be. Turning them into a Date and an Integer — or refusing, with
# a message naming the field — is a separate job from deciding whether a raise
# is allowed, so it lives in a separate object.
#
# It also folds the command's exceptions back into `errors`. An HR manager
# filling in a form does not care whether the rejection came from parsing, from
# a missing exchange rate, or from the effective-dating rule; they care which
# field to fix.
class SalaryChangeForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Deliberately untyped. Declaring this as `:integer` would cast "95000.50"
  # to 95000 and accept it, silently losing fifty pence of somebody's salary.
  # Keeping the raw value lets numericality reject it outright.
  attribute :amount_minor
  attribute :currency_code, :string
  attribute :effective_from, :date
  attribute :reason, :string
  attribute :note, :string

  validates :amount_minor,
            numericality: { only_integer: true, greater_than: 0, message: "must be a whole number of minor units" }
  # A malformed date casts to nil, so presence covers both "missing" and
  # "2026-02-30" — and the message has to be true of both.
  validates :effective_from, presence: { message: "must be a date in YYYY-MM-DD form" }
  validates :reason,
            inclusion: { in: Compensation::REASONS.keys.map(&:to_s),
                         message: "must be one of: #{Compensation::REASONS.keys.join(', ')}" }
  validates :currency_code, presence: true
  validate :currency_must_be_known

  attr_reader :employee, :compensation

  def initialize(employee:, **attributes)
    @employee = employee
    super(**attributes)
  end

  def save
    return false unless valid?

    @compensation = RecordSalaryChange.call(
      employee: employee,
      amount_minor: Integer(amount_minor),
      currency_code: currency_code,
      effective_from: effective_from,
      reason: reason,
      note: note
    )
    true
  rescue RecordSalaryChange::BackdatedChange => error
    errors.add(:effective_from, error.message)
    false
  rescue ExchangeRate::NotFound => error
    errors.add(:currency_code, error.message)
    false
  end

  # Codes are canonical uppercase everywhere else, so "usd" is accepted rather
  # than rejected for a reason the caller cannot see.
  def currency_code
    super.to_s.strip.upcase.presence
  end

  private

  # Without this the unknown code reaches the database and comes back as a
  # foreign key violation, which is a 500 describing a constraint name.
  def currency_must_be_known
    return if currency_code.blank?
    return if Currency.exists?(code: currency_code)

    errors.add(:currency_code, "is not a currency this system holds rates for")
  end
end
