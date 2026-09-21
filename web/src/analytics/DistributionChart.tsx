import type { PayrollBand } from "../api/types";
import { formatMoneyCompact, formatNumber } from "../format";

/**
 * Where people actually sit, as a table with bars drawn on it.
 *
 * A table rather than a canvas or an SVG plot: every figure is readable by a
 * screen reader and selectable by a mouse, the bars are one CSS width, and
 * there is no charting dependency to keep current for one histogram. The bars
 * are decoration over real numbers, which is why they are `aria-hidden`.
 */
export function DistributionChart({ bands }: { bands: PayrollBand[] }) {
  // Scaled to the tallest band, not to the headcount. Scaling to the total
  // would leave every bar near-empty and the shape unreadable.
  const tallest = Math.max(...bands.map((band) => band.headcount), 1);
  const total = bands.reduce((sum, band) => sum + band.headcount, 0);

  return (
    <div className="table-scroll">
      <table className="table">
        <thead>
          <tr>
            <th scope="col">Salary band</th>
            <th scope="col" className="table__cell--numeric">
              Employees
            </th>
            <th scope="col">Share</th>
          </tr>
        </thead>
        <tbody>
          {bands.map((band) => (
            <tr key={band.from.amount_minor}>
              <td className="chart__band">
                {formatMoneyCompact(band.from)} – {formatMoneyCompact(band.to)}
              </td>
              <td className="table__cell--numeric">{formatNumber(band.headcount)}</td>
              <td>
                <div className="chart__row">
                  <span
                    className="chart__bar"
                    style={{ width: `${(band.headcount / tallest) * 100}%` }}
                    aria-hidden="true"
                  />
                  <span className="chart__value">{share(band.headcount, total)}</span>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/**
 * One decimal place, because several bands here are under 1% and rounding them
 * all to "0%" would suggest the tail is empty when it holds ninety-six people.
 */
function share(headcount: number, total: number): string {
  if (total === 0) return "0%";

  return `${((headcount / total) * 100).toFixed(1)}%`;
}
