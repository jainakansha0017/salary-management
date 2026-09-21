import type { BreakdownDimension, Money, PayrollSummary } from "../api/types";
import { QueryState } from "../components/QueryState";
import { usePayrollBreakdown, usePayrollSummary } from "../analytics/api";
import { AnalyticsFilters } from "../analytics/AnalyticsFilters";
import { BreakdownTable } from "../analytics/BreakdownTable";
import { DistributionChart } from "../analytics/DistributionChart";
import { DIMENSIONS, useAnalyticsParams } from "../analytics/useAnalyticsParams";
import { formatDate, formatMoneyOrDash, formatNumber, NOT_APPLICABLE } from "../format";

export function AnalyticsPage() {
  const { params, update, clear } = useAnalyticsParams();
  const summary = usePayrollSummary(params);
  const breakdown = usePayrollBreakdown(params);

  return (
    <section className="page">
      <header className="page__header">
        <div>
          <h1 className="page__title">Payroll analytics</h1>
          <p className="page__subtitle">
            {params.as_of ? `As of ${formatDate(params.as_of)}` : "As of today"}
          </p>
        </div>
      </header>

      <AnalyticsFilters params={params} onChange={update} onClear={clear} />

      <QueryState
        query={summary}
        emptyWhen={(data) => data.headcount === 0}
        emptyMessage="Nobody matches these filters, so there is nothing to total."
      >
        {(data) => (
          <>
            <Headlines summary={data} />

            <h2 className="card__title">How pay is distributed</h2>
            <DistributionChart bands={data.distribution} />

            <h2 className="card__title">Spread</h2>
            <Percentiles summary={data} />
          </>
        )}
      </QueryState>

      <div className="section-head">
        <h2 className="card__title">Compare groups</h2>
        <DimensionPicker
          value={params.dimension ?? "department"}
          onChange={(dimension) => update({ dimension })}
        />
      </div>

      {params.dimension === "job_level" && (
        <p className="note">
          Levels are not comparable across countries. An L5 in India is paid less than an L3 in the
          United States, so a low average here is usually where a group works, not how it is paid.
          Filter to one country before reading these as pay differences.
        </p>
      )}

      <QueryState
        query={breakdown}
        emptyWhen={(data) => data.groups.length === 0}
        emptyMessage="Nobody matches these filters."
      >
        {(data) => <BreakdownTable groups={data.groups} />}
      </QueryState>
    </section>
  );
}

/**
 * Named regions, not bare cards. "Median" appears three times on this page —
 * here, in the percentile strip, and as a column of the comparison table — and
 * without a label on each block there is no way for a screen reader, or a test,
 * to say which one is meant.
 */
function Headlines({ summary }: { summary: PayrollSummary }) {
  return (
    <section className="card" aria-label="Payroll totals">
      <dl className="facts">
        <Headline term="Employees" value={formatNumber(summary.headcount)} />
        <Headline term="Total payroll" value={formatMoneyOrDash(summary.total)} />
        <Headline term="Average" value={formatMoneyOrDash(summary.average)} />
        {/* Beside the average deliberately. The gap between the two is the
            first thing worth noticing: where it is wide, the average is being
            pulled by a few large salaries and is the wrong number to plan on. */}
        <Headline term="Median" value={formatMoneyOrDash(summary.percentiles["median"] ?? null)} />
        <Headline term="Lowest" value={formatMoneyOrDash(summary.minimum)} />
        <Headline term="Highest" value={formatMoneyOrDash(summary.maximum)} />
      </dl>
    </section>
  );
}

function Headline({ term, value }: { term: string; value: string }) {
  return (
    <div className="facts__item">
      <dt className="facts__term">{term}</dt>
      <dd className="facts__value">
        <span className="facts__headline">{value}</span>
      </dd>
    </div>
  );
}

/** The labels the API uses, in the order they occur rather than alphabetically. */
const PERCENTILES: { key: string; label: string }[] = [
  { key: "p10", label: "10th" },
  { key: "p25", label: "25th" },
  { key: "median", label: "Median" },
  { key: "p75", label: "75th" },
  { key: "p90", label: "90th" },
];

function Percentiles({ summary }: { summary: PayrollSummary }) {
  return (
    <section className="card" aria-label="Salary percentiles">
      <dl className="facts">
        {PERCENTILES.map(({ key, label }) => (
          <div className="facts__item" key={key}>
            <dt className="facts__term">{label}</dt>
            <dd className="facts__value">
              <span className="facts__figure">{money(summary.percentiles[key])}</span>
            </dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

function money(value: Money | null | undefined): string {
  return value ? formatMoneyOrDash(value) : NOT_APPLICABLE;
}

const DIMENSION_LABELS: Record<BreakdownDimension, string> = {
  country: "Country",
  department: "Department",
  job_level: "Level",
};

/**
 * Radios rather than a select. There are three options, they are the subject of
 * the table below, and a closed dropdown hides two thirds of what this page can
 * answer.
 */
function DimensionPicker({
  value,
  onChange,
}: {
  value: BreakdownDimension;
  onChange: (dimension: BreakdownDimension) => void;
}) {
  return (
    <fieldset className="segmented">
      <legend className="sr-only">Group by</legend>
      {DIMENSIONS.map((dimension) => (
        <label
          key={dimension}
          className={
            dimension === value ? "segmented__option segmented__option--on" : "segmented__option"
          }
        >
          <input
            type="radio"
            name="dimension"
            className="sr-only"
            value={dimension}
            checked={dimension === value}
            onChange={() => onChange(dimension)}
          />
          {DIMENSION_LABELS[dimension]}
        </label>
      ))}
    </fieldset>
  );
}
