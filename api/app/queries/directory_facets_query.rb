# The values the directory can actually be filtered by.
#
# The client cannot hard-code these. Department ids are assigned by the database
# and differ between a developer's machine and production, so a filter panel
# built from a constant would send ids that mean a different department or no
# department at all.
#
# Derived from the data rather than from a list of what ought to exist, so an
# option can never be offered that matches nobody, and a country added by the
# next seed appears without a deploy of the client.
class DirectoryFacetsQuery
  Facets = Struct.new(:countries, :departments, :job_levels, keyword_init: true)

  def call
    Facets.new(countries: countries, departments: departments, job_levels: job_levels)
  end

  private

  # Distinct over an indexed column, which Postgres answers from the index
  # rather than by reading the table.
  def countries
    Employee.distinct.order(:country_code).pluck(:country_code)
  end

  # Every department, not only those with someone in them: an empty department
  # is a legitimate thing to filter for, and finding nobody is the answer.
  def departments
    Department.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } }
  end

  # Sorted as strings, which is right for L1..L8 and stays right for any scheme
  # that is ordered lexically. A scheme where it is not — "Senior", "Staff",
  # "Principal" — would need an explicit rank on the level, which is a change to
  # the domain rather than to this query.
  def job_levels
    Employee.distinct.order(:job_level).pluck(:job_level)
  end
end
