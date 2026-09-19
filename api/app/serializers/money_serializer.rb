# Money crosses the wire the way it is stored: an integer and the number of
# decimal places that integer implies.
#
# JSON numbers are IEEE 754 doubles, so serialising 1234.56 hands the client a
# value that cannot be represented exactly and invites it to do arithmetic on
# it. Sending minor units keeps the amount exact and leaves formatting to the
# browser, which knows the user's locale and already has Intl.NumberFormat.
class MoneySerializer
  def self.call(amount_minor:, currency:)
    {
      amount_minor: amount_minor,
      currency_code: currency.code,
      # The client cannot infer this: JPY has none, USD has two.
      minor_unit: currency.minor_unit
    }
  end
end
