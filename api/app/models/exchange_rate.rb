class ExchangeRate < ApplicationRecord
  # Raised rather than returning nil, because a missing rate means a figure
  # cannot be computed. Silently skipping it would understate payroll cost,
  # which is worse than failing loudly.
  class NotFound < StandardError
    def initialize(from:, to:, on:)
      super("No exchange rate from #{from} to #{to} effective on #{on}")
    end
  end

  belongs_to :from_currency, class_name: "Currency",
             foreign_key: :from_currency_code, primary_key: :code, inverse_of: false
  belongs_to :to_currency, class_name: "Currency",
             foreign_key: :to_currency_code, primary_key: :code, inverse_of: false

  validates :rate, numericality: { greater_than: 0 }
  validates :effective_from, presence: true
  validate :period_must_be_ordered

  # Half-open period: effective on the start date, no longer effective on the
  # end date. That makes consecutive periods meet exactly without overlapping
  # or leaving a gap.
  scope :effective_on, ->(date) {
    where(effective_from: ..date)
      .where("exchange_rates.effective_to IS NULL OR exchange_rates.effective_to > ?", date)
  }

  scope :for_pair, ->(from:, to:) {
    where(from_currency_code: from, to_currency_code: to)
  }

  def self.effective!(from:, to:, on:)
    for_pair(from: from, to: to).effective_on(on).first ||
      raise(NotFound.new(from: from, to: to, on: on))
  end

  # Converts an integer amount in from_currency's minor units into an integer
  # amount in to_currency's minor units.
  #
  # The scale factor matters: currencies do not share an exponent, so
  # converting JPY (no minor unit) to USD (two) is not just a multiplication by
  # the rate. Ignoring this is a silent factor-of-100 bug.
  def convert(amount_minor)
    scale = BigDecimal(10)**(to_currency.minor_unit - from_currency.minor_unit)

    (BigDecimal(amount_minor) * rate * scale).round
  end

  private

  def period_must_be_ordered
    return if effective_to.blank? || effective_from.blank?
    return if effective_to > effective_from

    errors.add(:effective_to, "must be after the start of the period")
  end
end
