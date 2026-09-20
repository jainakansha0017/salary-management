import { directoryExportUrl, useDirectory } from "../employees/api";
import type { DirectoryParams } from "../employees/api";
import { FilterPanel } from "../employees/FilterPanel";
import { nextSort, useDirectoryParams } from "../employees/useDirectoryParams";
import { formatDate, formatMoneyOrDash, formatNumber } from "../format";
import { QueryState } from "../components/QueryState";
import { Pagination } from "../components/Pagination";
import type { EmployeeSummary } from "../api/types";

export function DirectoryPage() {
  const { params, update, goToPage, clear } = useDirectoryParams();
  const directory = useDirectory(params);

  return (
    <section className="page">
      <header className="page__header">
        <div>
          <h1 className="page__title">Employee directory</h1>
          {directory.data && (
            <p className="page__subtitle">
              {formatNumber(directory.data.meta.total_count)} employees
            </p>
          )}
        </div>

        {/* An anchor, not a button: the browser does the download itself, so
            nothing is held in memory and the filename the server sets is
            honoured. It carries the filters on screen, so the file is the list
            being looked at rather than everyone. */}
        <a className="button button--secondary" href={directoryExportUrl(params)} download>
          Export CSV
        </a>
      </header>

      <FilterPanel params={params} onChange={update} onClear={clear} />

      <QueryState
        query={directory}
        emptyWhen={(page) => page.data.length === 0}
        emptyMessage="Nobody matches these filters."
      >
        {(page) => (
          <>
            <EmployeeTable
              employees={page.data}
              params={params}
              onSort={(column) => update(nextSort(params, column))}
            />
            <Pagination
              page={page.meta.page}
              totalPages={page.meta.total_pages}
              totalCount={page.meta.total_count}
              pageSize={page.meta.page_size}
              onGoTo={goToPage}
            />
          </>
        )}
      </QueryState>
    </section>
  );
}

const COLUMNS = [
  { key: "name", label: "Employee", sortable: true, numeric: false },
  { key: "department", label: "Department", sortable: false, numeric: false },
  { key: "job_level", label: "Level", sortable: false, numeric: false },
  { key: "country_code", label: "Country", sortable: false, numeric: false },
  { key: "hired_on", label: "Hired", sortable: true, numeric: false },
  { key: "salary", label: "Salary", sortable: true, numeric: true },
  // The local amount is what the person is paid; the base amount is the only
  // one two rows can be compared on. Both are shown rather than the UI
  // choosing, because the answer differs by question.
  //
  // The sort belongs to the pair, and it is the base amount that is sorted —
  // ordering mixed currencies by their local number would rank ¥8,000,000 above
  // $200,000. The header sits on the local column because that is the one
  // someone looks for.
  { key: "base", label: "In base currency", sortable: false, numeric: true },
] as const;

function EmployeeTable({
  employees,
  params,
  onSort,
}: {
  employees: EmployeeSummary[];
  params: DirectoryParams;
  onSort: (column: string) => void;
}) {
  return (
    <div className="table-scroll">
      <table className="table">
        <thead>
          <tr>
            {COLUMNS.map((column) => (
              <th
                key={column.key}
                scope="col"
                className={column.numeric ? "table__cell--numeric" : undefined}
                // Announced by a screen reader, and the hook a test uses to
                // assert the table is sorted by what it claims to be.
                aria-sort={ariaSort(params, column.key, column.sortable)}
              >
                {column.sortable ? (
                  <button type="button" className="table__sort" onClick={() => onSort(column.key)}>
                    {column.label}
                    <SortMarker active={params.sort === column.key} direction={params.direction} />
                  </button>
                ) : (
                  column.label
                )}
              </th>
            ))}
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

function ariaSort(
  params: DirectoryParams,
  column: string,
  sortable: boolean,
): "ascending" | "descending" | "none" | undefined {
  if (!sortable) return undefined;
  if (params.sort !== column) return "none";

  return params.direction === "desc" ? "descending" : "ascending";
}

/** An arrow on the active column only; a marker on every header is noise. */
function SortMarker({ active, direction }: { active: boolean; direction?: string | undefined }) {
  if (!active) return null;

  return (
    <span className="table__sort-marker" aria-hidden="true">
      {direction === "desc" ? "\u2193" : "\u2191"}
    </span>
  );
}
