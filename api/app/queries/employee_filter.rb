# The part of a directory request that decides *which people* a question is
# about: a search term and the three facets HR actually filters on.
#
# It is separate from `EmployeeDirectoryQuery` because analytics asks the same
# question of the same population — "median pay in Engineering in Poland" is the
# directory's filters with a different verb. Sharing the object means a filter
# cannot mean one thing on the list page and something else on the dashboard.
#
# Status is deliberately not here. The directory filters people by their
# employment dates; analytics derives its population from which compensation
# period is effective on a date, which is a different question with a different
# answer.
class EmployeeFilter
  def initialize(params = {})
    @params = params.to_h.symbolize_keys
  end

  def apply(relation)
    relation = relation.search(search_term) if search_term.present?
    relation = relation.where(country_code: countries) if countries.any?
    relation = relation.where(department_id: departments) if departments.any?
    relation = relation.where(job_level: job_levels) if job_levels.any?
    relation
  end

  # Echoed back to the client so it can show what was actually applied, rather
  # than having to guess how its parameters were interpreted.
  def applied
    {
      search: search_term,
      country_code: countries,
      department_id: departments,
      job_level: job_levels
    }
  end

  def search_term
    @search_term ||= params[:q].to_s.strip
  end

  private

  attr_reader :params

  def countries
    @countries ||= Array(params[:country_code]).map { |code| code.to_s.strip.upcase }.reject(&:empty?)
  end

  def departments
    @departments ||= Array(params[:department_id]).map { |id| Integer(id, exception: false) }.compact
  end

  def job_levels
    @job_levels ||= Array(params[:job_level]).map { |level| level.to_s.strip }.reject(&:empty?)
  end
end
