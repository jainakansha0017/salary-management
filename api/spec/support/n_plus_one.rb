# N+1 queries are the most likely way the directory endpoint silently degrades
# at 10,000 employees. Rather than trusting review to catch them, specs tagged
# `:n_plus_one` fail if one occurs.
#
#   it "loads the directory in a fixed number of queries", :n_plus_one do
#     ...
#   end
require "prosopite"

RSpec.configure do |config|
  config.around(:each, :n_plus_one) do |example|
    Prosopite.rails_logger = false
    Prosopite.raise = true
    Prosopite.scan
    example.run
  ensure
    Prosopite.finish
  end
end
