import { Link, useParams } from "react-router-dom";
import { useEmployee } from "../employees/api";
import { SalaryChangeForm } from "../employees/SalaryChangeForm";
import { QueryState } from "../components/QueryState";
import {
  formatDate,
  formatMoney,
  formatMoneyOrDash,
  formatReason,
  NOT_APPLICABLE,
} from "../format";
import type { Compensation, EmployeeDetail } from "../api/types";

export function EmployeePage() {
  const { id = "" } = useParams();
  const employee = useEmployee(id);

  return (
    <section className="page">
      {/* A link, not `history.back()`: this page is reachable from a pasted URL
          as well as from the table, and a back button that does nothing on
          arrival is worse than one that always goes somewhere sensible. */}
      <Link className="page__back" to="/employees">
        &larr; Directory
      </Link>

      <QueryState query={employee}>
        {(person) => {
          // The currency is taken from the pay being replaced rather than
          // chosen: this form records a raise, not a relocation, and offering a
          // currency picker here would imply that converting someone's existing
          // salary is a thing this screen can do.
          const currency = person.current_salary?.amount ?? person.salary_history[0]?.amount;

          return (
            <>
              <Identity person={person} />
              <CurrentPay person={person} />

              {currency ? (
                <SalaryChangeForm employeeId={id} currency={currency} />
              ) : (
                <p className="state state--empty">
                  This employee has no salary on record, so there is nothing to change.
                </p>
              )}

              <History history={person.salary_history} />
            </>
          );
        }}
      </QueryState>
    </section>
  );
}

function Identity({ person }: { person: EmployeeDetail }) {
  return (
    <header className="page__header">
      <div>
        <h1 className="page__title">{person.full_name}</h1>
        <p className="page__subtitle">
          {person.employee_number} · {person.job_title}
        </p>
      </div>

      {!person.active && (
        <span className="badge badge--quiet">Left {formatDate(person.ended_on)}</span>
      )}
    </header>
  );
}

function CurrentPay({ person }: { person: EmployeeDetail }) {
  const salary = person.current_salary;

  return (
    <div className="card">
      <dl className="facts">
        <Fact term="Current salary">
          {salary ? (
            <>
              <span className="facts__headline">{formatMoney(salary.amount)}</span>
              {/* Shown only when it says something the line above does not. */}
              {salary.base_amount.currency_code !== salary.amount.currency_code && (
                <span className="facts__aside">{formatMoney(salary.base_amount)}</span>
              )}
            </>
          ) : (
            <span className="facts__headline">{NOT_APPLICABLE}</span>
          )}
        </Fact>
        <Fact term="Since">{salary ? formatDate(salary.effective_from) : NOT_APPLICABLE}</Fact>
        <Fact term="Department">{person.department}</Fact>
        <Fact term="Level">{person.job_level}</Fact>
        <Fact term="Country">{person.country_code}</Fact>
        <Fact term="Hired">{formatDate(person.hired_on)}</Fact>
        <Fact term="Email">{person.email}</Fact>
      </dl>
    </div>
  );
}

function Fact({ term, children }: { term: string; children: React.ReactNode }) {
  return (
    <div className="facts__item">
      <dt className="facts__term">{term}</dt>
      <dd className="facts__value">{children}</dd>
    </div>
  );
}

function History({ history }: { history: Compensation[] }) {
  return (
    <>
      <h2 className="card__title">Salary history</h2>
      <div className="table-scroll">
        <table className="table">
          <thead>
            <tr>
              <th scope="col">From</th>
              <th scope="col">To</th>
              <th scope="col" className="table__cell--numeric">
                Amount
              </th>
              <th scope="col" className="table__cell--numeric">
                In base currency
              </th>
              <th scope="col">Reason</th>
              <th scope="col">Note</th>
            </tr>
          </thead>
          <tbody>
            {history.map((period) => (
              <tr key={period.id}>
                <td>
                  {formatDate(period.effective_from)}
                  <PeriodBadge period={period} />
                </td>
                <td>{period.effective_to ? formatDate(period.effective_to) : NOT_APPLICABLE}</td>
                <td className="table__cell--numeric">{formatMoney(period.amount)}</td>
                <td className="table__cell--numeric">{formatMoneyOrDash(period.base_amount)}</td>
                <td>{formatReason(period.reason)}</td>
                <td className="cell__secondary">{period.note ?? NOT_APPLICABLE}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

/**
 * Three states, not two. A raise recorded today to start in January is
 * open-ended *and* not being paid, and the server draws that distinction with
 * `current` — so a row that is neither current nor closed is scheduled, and
 * saying so is the difference between "their salary is wrong" and "their raise
 * has not started yet".
 */
function PeriodBadge({ period }: { period: Compensation }) {
  if (period.current) return <span className="badge">Current</span>;
  if (period.effective_to === null) return <span className="badge badge--quiet">Scheduled</span>;

  return null;
}
