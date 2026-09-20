import { useDirectory } from "../employees/api";
import { formatDate, formatMoneyOrDash, formatNumber } from "../format";
import { QueryState } from "../components/QueryState";
import type { EmployeeSummary } from "../api/types";

export function DirectoryPage() {
  const directory = useDirectory({ page: 1 });

  return (
    <section className="page">
      <header className="page__header">
        <h1 className="page__title">Employee directory</h1>
        {directory.data && (
          <p className="page__subtitle">
            {formatNumber(directory.data.meta.total_count)} employees
          </p>
        )}
      </header>

      <QueryState query={directory} emptyWhen={(page) => page.data.length === 0}>
        {(page) => <EmployeeTable employees={page.data} />}
      </QueryState>
    </section>
  );
}

function EmployeeTable({ employees }: { employees: EmployeeSummary[] }) {
  return (
    <div className="table-scroll">
      <table className="table">
        <thead>
          <tr>
            <th scope="col">Employee</th>
            <th scope="col">Department</th>
            <th scope="col">Level</th>
            <th scope="col">Country</th>
            <th scope="col">Hired</th>
            <th scope="col" className="table__cell--numeric">
              Salary
            </th>
            {/* The local amount is what the person is paid; the base amount is
                the only one two rows can be compared on. Both are shown rather
                than the UI choosing, because the answer differs by question. */}
            <th scope="col" className="table__cell--numeric">
              In base currency
            </th>
          </tr>
        </thead>
        <tbody>
          {employees.map((employee) => (
            <tr key={employee.id}>
              <td>
                <span className="cell__primary">{employee.full_name}</span>
                <span className="cell__secondary">
                  {employee.employee_number} · {employee.job_title}
                </span>
              </td>
              <td>{employee.department}</td>
              <td>{employee.job_level}</td>
              <td>{employee.country_code}</td>
              <td>{formatDate(employee.hired_on)}</td>
              <td className="table__cell--numeric">
                {formatMoneyOrDash(employee.current_salary?.amount)}
              </td>
              <td className="table__cell--numeric">
                {formatMoneyOrDash(employee.current_salary?.base_amount)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
