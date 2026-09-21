import { Facets, SearchField } from "../employees/FilterPanel";
import type { AnalyticsParams } from "./api";

interface Props {
  params: AnalyticsParams;
  onChange: (patch: Partial<AnalyticsParams>) => void;
  onClear: () => void;
}

/**
 * The same facets as the directory, plus a date and minus a status.
 *
 * Status is absent because it would be a control that does nothing: payroll
 * cost is a question about who is being paid, and `as_of` already answers
 * "who counted then" — a leaver simply has no salary in effect on a later date,
 * so they drop out without a second definition of "active".
 */
export function AnalyticsFilters({ params, onChange, onClear }: Props) {
  return (
    <div className="filters">
      <SearchField
        id="analytics-search"
        value={params.q ?? ""}
        onChange={(q) => onChange({ q })}
        placeholder="Name, email or employee number"
      />

      <AsOfField value={params.as_of ?? ""} onChange={(as_of) => onChange({ as_of })} />

      <Facets params={params} onChange={onChange} prefix="analytics" />

      {hasFilters(params) && (
        <button type="button" className="filters__clear" onClick={onClear}>
          Clear all
        </button>
      )}
    </div>
  );
}

/**
 * What makes this a payroll tool rather than a report of today.
 *
 * Because pay is effective-dated and append-only, "what did this cost in
 * January" is the same query with a different date — no snapshot table, no
 * month-end job. Empty means today, which is also what the server assumes.
 */
function AsOfField({ value, onChange }: { value: string; onChange: (value: string) => void }) {
  return (
    <div className="filters__field">
      <label className="filters__label" htmlFor="analytics-as-of">
        As of
      </label>
      <input
        id="analytics-as-of"
        className="input"
        type="date"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
    </div>
  );
}

function hasFilters(params: AnalyticsParams): boolean {
  return Boolean(
    params.q ||
    params.as_of ||
    params.country_code?.length ||
    params.department_id?.length ||
    params.job_level?.length,
  );
}
