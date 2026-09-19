# N+1 queries are the most likely way the directory endpoint silently degrades
# at 10,000 employees. Rather than trusting review to catch them, specs tagged
# `:n_plus_one` fail if one occurs.
#
#   it "loads the directory in a fixed number of queries", :n_plus_one do
#     ignoring_n_plus_one { 25.times { create(:employee) } }
#     ...
#   end
require "prosopite"

module NPlusOneHelpers
  # Building fixtures issues the same INSERT and the same lookup once per
  # record, which is an N+1 by Prosopite's definition and irrelevant by ours.
  # Only the code under test should be scanned.
  def ignoring_n_plus_one
    Prosopite.pause
    yield
  ensure
    Prosopite.resume
  end
end

RSpec.configure do |config|
  config.include NPlusOneHelpers

  config.around(:each, :n_plus_one) do |example|
    Prosopite.rails_logger = false
    Prosopite.raise = true
    Prosopite.scan
    example.run
  ensure
    Prosopite.finish
  end
end
