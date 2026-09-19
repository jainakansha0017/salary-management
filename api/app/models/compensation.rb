class Compensation < ApplicationRecord
  REASONS = {
    hire: "hire",
    merit_increase: "merit_increase",
    promotion: "promotion",
    market_adjustment: "market_adjustment",
    correction: "correction"
  }.freeze

  belongs_to :employee
  belongs_to :currency, foreign_key: :currency_code, primary_key: :code, inverse_of: false
  belongs_to :base_currency, class_name: "Currency",
             foreign_key: :base_currency_code, primary_key: :code, inverse_of: false

  enum :reason, REASONS, validate: true

  validates :amount_minor, numericality: { only_integer: true, greater_than: 0 }
  validates :amount_base_minor, numericality: { only_integer: true, greater_than: 0 }
  validates :exchange_rate_used, numericality: { greater_than: 0 }
  validates :effective_from, presence: true
  validate :period_must_be_ordered

  # Half-open, matching ExchangeRate: effective on the start date, no longer
  # effective on the end date.
  scope :current, -> { where(effective_to: nil) }
  scope :effective_on, ->(date) {
    where(effective_from: ..date)
      .where("compensations.effective_to IS NULL OR compensations.effective_to > ?", date)
  }
  scope :newest_first, -> { order(effective_from: :desc) }

  def current?
    effective_to.nil?
  end

  def amount
    currency.to_major(amount_minor)
  end

  def amount_base
    base_currency.to_major(amount_base_minor)
  end

  private

  def period_must_be_ordered
    return if effective_to.blank? || effective_from.blank?
    return if effective_to > effective_from

    errors.add(:effective_to, "must be after the start of the period")
  end
end
