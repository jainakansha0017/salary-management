import type { BreakdownGroup, Money } from "../api/types";
import { formatMoneyCompact, formatMoneyOrDash, formatNumber, NOT_APPLICABLE } from "../format";

/**
 * Comparison between groups, with the spread shown rather than only the
 * average.
 *
 * The average alone is what makes a pay review go wrong: two departments
 * averaging the same can have completely different shapes, and it is the shape
 * that says whether a band is wide, whether seniors are clustered, whether
 * anyone is stranded. So each row carries the middle half of its group —
 * p25 to p75, with the median marked — drawn on a scale shared by every row so
 * the bars can honestly be compared against each other.
 */
export function BreakdownTable({ groups }: { groups: BreakdownGroup[] }) {
  const scale = Math.max(...groups.map(upperBound), 1);

  return (
    <div className="table-scroll">
      <table className="table">
        <thead>
          <tr>
            <th scope="col">Group</th>
            <th scope="col" className="table__cell--numeric">
              Headcount
            </th>
            <th scope="col" className="table__cell--numeric">
              Total
            </th>
            <th scope="col" className="table__cell--numeric">
              Average
            </th>
            <th scope="col" className="table__cell--numeric">
              Median
            </th>
            <th scope="col">Middle half (p25–p75)</th>
          </tr>
        </thead>
        <tbody>
          {groups.map((group) => (
            <tr key={group.key}>
              <td className="cell__primary">{group.label}</td>
              <td className="table__cell--numeric">{formatNumber(group.headcount)}</td>
              <td className="table__cell--numeric">{formatMoneyOrDash(group.total)}</td>
              <td className="table__cell--numeric">{formatMoneyOrDash(group.average)}</td>
              <td className="table__cell--numeric">
                {formatMoneyOrDash(percentile(group, "median"))}
              </td>
              <td>
                <Spread group={group} scale={scale} />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/**
 * The box of a box plot, without the whiskers — the API reports quartiles, not
 * outlier bounds, and drawing whiskers from data that does not describe them
 * would be an invented figure.
 */
function Spread({ group, scale }: { group: BreakdownGroup; scale: number }) {
  const lower = percentile(group, "p25");
  const median = percentile(group, "median");
  const upper = percentile(group, "p75");

  if (!lower || !upper) {
    return <span className="chart__value">{NOT_APPLICABLE}</span>;
  }

  const left = (lower.amount_minor / scale) * 100;
  const width = ((upper.amount_minor - lower.amount_minor) / scale) * 100;

  return (
    <div className="chart__row">
      <span className="chart__track" aria-hidden="true">
        <span className="chart__box" style={{ left: `${left}%`, width: `${width}%` }}>
          {median && (
            <span
              className="chart__median"
              style={{
                left: `${((median.amount_minor - lower.amount_minor) / (upper.amount_minor - lower.amount_minor)) * 100}%`,
              }}
            />
          )}
        </span>
      </span>
      {/* The bar is decoration; this is the readable version of it. */}
      <span className="chart__value">
        {formatMoneyCompact(lower)} – {formatMoneyCompact(upper)}
      </span>
    </div>
  );
}

function percentile(group: BreakdownGroup, key: string): Money | null {
  return group.percentiles[key] ?? null;
}

/** How far right this row reaches, so every row can share one scale. */
function upperBound(group: BreakdownGroup): number {
  return percentile(group, "p75")?.amount_minor ?? 0;
}
