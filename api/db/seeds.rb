# Builds an ACME-sized organisation: 10,000 employees across ten countries,
# each with salary history.
#
#   bin/rails db:seed                 # 10,000 employees
#   EMPLOYEE_COUNT=200 bin/rails db:seed
#
# The generator is seeded with a fixed value, so running this twice produces
# the same organisation. That matters for a demo, and it means a number quoted
# in the README can be checked rather than taken on trust.

employee_count = Integer(ENV.fetch("EMPLOYEE_COUNT", 10_000))

# Seeding replaces the organisation rather than adding a second one. Guarded,
# because pointing this at a database that already holds real salary data
# would be unrecoverable.
if Employee.exists? && !ActiveModel::Type::Boolean.new.cast(ENV["FORCE"])
  abort <<~MESSAGE
    This database already contains #{Employee.count} employees.
    Re-run with FORCE=true to replace them.
  MESSAGE
end

ActiveRecord::Base.transaction do
  Compensation.delete_all
  Employee.delete_all
  Department.delete_all
  ExchangeRate.delete_all
  Currency.delete_all
end

puts "Seeding #{employee_count} employees..."
started_at = Time.current

Seeds::OrganisationSeeder.new(employee_count: employee_count).call

puts "  took #{(Time.current - started_at).round(1)}s"
