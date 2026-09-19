# The directory row plus the thing the directory cannot show: how this person's
# pay got to where it is.
#
# It composes the summary rather than redefining it, so a field cannot mean one
# thing in the list and something else on the detail page.
class EmployeeDetailSerializer
  def initialize(employee)
    @employee = employee
  end

  def as_json
    EmployeeSummarySerializer.new(employee).as_json.merge(
      department_id: employee.department_id,
      salary_history: salary_history
    )
  end

  private

  attr_reader :employee

  # Newest first, because the question is almost always "what happened
  # recently". Sorted in Ruby rather than in SQL: the records are already
  # loaded and a career is a handful of rows, so re-querying to reorder them
  # would cost a round trip to save nothing.
  def salary_history
    employee.compensations
            .sort_by(&:effective_from)
            .reverse
            .map { |compensation| CompensationSerializer.new(compensation).as_json }
  end
end
