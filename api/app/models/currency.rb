class Currency < ApplicationRecord
  self.primary_key = :code

  validates :code, presence: true, format: { with: /\A[A-Z]{3}\z/, message: "must be an ISO 4217 code" }
  validates :name, :symbol, presence: true
  validates :minor_unit, numericality: { only_integer: true, in: 0..4 }

  normalizes :code, with: ->(code) { code.strip.upcase }

  # The factor between a currency's major and minor units: 100 for USD, 1 for
  # JPY. Amounts are stored as integers in minor units, so this is what turns a
  # stored value back into something a person recognises.
  def subunit_factor
    10**minor_unit
  end

  def to_major(amount_minor)
    BigDecimal(amount_minor) / subunit_factor
  end
end
