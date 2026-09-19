# Compensation is effective-dated, so almost every domain assertion depends on
# "today". Specs freeze time rather than relying on the real clock, which keeps
# them deterministic and stops them breaking at a year boundary.
RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers
end
