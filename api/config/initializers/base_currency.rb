# The currency every salary is normalised into for comparison and aggregation.
#
# Held in configuration rather than hardcoded because it is an organisational
# choice, but note that changing it is not a runtime toggle: stored base
# amounts would need backfilling, as recorded in ADR-3.
Rails.application.config.x.base_currency_code = ENV.fetch("BASE_CURRENCY_CODE", "USD")
