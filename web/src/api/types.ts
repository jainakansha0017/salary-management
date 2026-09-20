// The API's contract, written down once.
//
// These are hand-maintained rather than generated. There are six endpoints and
// a generator would be more machinery than the thing it generates; the cost is
// that a server change has to be mirrored here, which the request specs on the
// Rails side make visible.

/**
 * Money never crosses the wire as a decimal (ADR-6). The exponent travels with
 * the amount, so a client cannot assume two decimal places and render
 * ¥15,000,000 as ¥150,000.00.
 */
export interface Money {
  amount_minor: number;
  currency_code: string;
  minor_unit: number;
}

export interface Salary {
  amount: Money;
  /** The same pay converted to the organisation's base currency, so a
   *  mixed-currency list can be compared without the client converting. */
  base_amount: Money;
  effective_from: string;
}

export interface EmployeeSummary {
  id: number;
  employee_number: string;
  full_name: string;
  email: string;
  country_code: string;
  department: string;
  job_title: string;
  job_level: string;
  hired_on: string;
  ended_on: string | null;
  active: boolean;
  /** Null, not zero: someone who has left is not someone paid nothing. */
  current_salary: Salary | null;
}

export type CompensationReason =
  "hire" | "merit_increase" | "promotion" | "market_adjustment" | "correction";

export interface Compensation {
  id: number;
  amount: Money;
  base_amount: Money;
  /** A string, because it is the audit trail for the conversion and rounding
   *  it into a double would make the figure unverifiable. */
  exchange_rate_used: string;
  effective_from: string;
  effective_to: string | null;
  /** Whether this is the pay being received today — not whether the period is
   *  open-ended. A raise agreed now to start in January is both. */
  current: boolean;
  reason: CompensationReason;
  note: string | null;
}

export interface EmployeeDetail extends EmployeeSummary {
  department_id: number;
  salary_history: Compensation[];
}

export interface AppliedFilters {
  search: string;
  country_code: string[];
  department_id: number[];
  job_level: string[];
  status?: string;
  sort?: string;
  direction?: string;
  as_of?: string;
  dimension?: string;
}

export interface PageMeta extends Record<string, unknown> {
  page: number;
  page_size: number;
  total_count: number;
  total_pages: number;
  applied: AppliedFilters;
}

export interface Paginated<T> {
  data: T[];
  meta: PageMeta;
}

export interface PayrollBand {
  from: Money;
  to: Money;
  headcount: number;
}

export interface PayrollSummary {
  headcount: number;
  total: Money | null;
  average: Money | null;
  minimum: Money | null;
  maximum: Money | null;
  percentiles: Record<string, Money | null>;
  distribution: PayrollBand[];
}

export type BreakdownDimension = "country" | "department" | "job_level";

export interface BreakdownGroup {
  key: string | number;
  label: string;
  headcount: number;
  total: Money | null;
  average: Money | null;
  percentiles: Record<string, Money | null>;
}

export interface PayrollBreakdown {
  dimension: BreakdownDimension;
  groups: BreakdownGroup[];
}

export interface DepartmentOption {
  id: number;
  name: string;
}

/**
 * What the directory can be filtered by. Served by the API rather than held as
 * a constant here, because department ids are assigned by the database and
 * differ between machines.
 */
export interface DirectoryFacets {
  countries: string[];
  departments: DepartmentOption[];
  job_levels: string[];
}

/** Every failure the API reports uses this one shape. */
export interface ApiErrorBody {
  code: string;
  message: string;
  /** Present when the problem belongs to particular inputs, keyed by field so
   *  a form can mark the right one. */
  details?: Record<string, string[]>;
}
