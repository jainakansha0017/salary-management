# One row of the directory: enough to identify a person and compare their pay,
# and nothing more. Salary history belongs to the detail view.
#
# Written by hand rather than through a serializer gem. There are two of these
# in the whole application, they are the API's contract with the UI, and a
# plain method makes that contract readable in one screen.
class EmployeeSummarySerializer
  def initialize(employee)
    @employee = employee
  end

  def as_json
    {
      id: employee.id,
      employee_number: employee.employee_number,
      full_name: employee.full_name,
      email: employee.email,
      country_code: employee.country_code,
      department: employee.department.name,
      job_title: employee.job_title,
      job_level: employee.job_level,
      hired_on: employee.hired_on,
      ended_on: employee.ended_on,
      active: employee.ended_on.nil?,
      current_salary: current_salary
    }
  end

  private

  attr_reader :employee

  # Null rather than omitted, and null rather than zero: someone who has left
  # has no current salary, and that is different from being paid nothing.
  def current_salary
    compensation = employee.effective_compensation
    return nil if compensation.nil?

    {
      amount: MoneySerializer.call(
        amount_minor: compensation.amount_minor,
        currency: compensation.currency
      ),
      # The same pay in the base currency, so the UI can sort and compare a
      # mixed-currency page without doing any conversion itself.
      base_amount: MoneySerializer.call(
        amount_minor: compensation.amount_base_minor,
        currency: compensation.base_currency
      ),
      effective_from: compensation.effective_from
    }
  end
end
