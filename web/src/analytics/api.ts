import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { getJson } from "../api/client";
import type { BreakdownDimension, PayrollBreakdown, PayrollSummary } from "../api/types";

/**
 * Exactly what `AnalyticsController` permits. Note what is missing: there is no
 * `status`, because a payroll cost is a question about who is being paid, and
 * no paging, because these endpoints return an organisation rather than a list.
 */
export interface AnalyticsParams {
  q?: string;
  /** The date the question is asked about. Omitted means today, per the API. */
  as_of?: string;
  dimension?: BreakdownDimension;
  country_code?: string[];
  department_id?: number[];
  job_level?: string[];
}

function fetchSummary(params: AnalyticsParams, signal: AbortSignal): Promise<PayrollSummary> {
  return getJson<{ data: PayrollSummary }>("/api/v1/analytics/summary", params, signal).then(
    (body) => body.data,
  );
}

function fetchBreakdown(params: AnalyticsParams, signal: AbortSignal): Promise<PayrollBreakdown> {
  return getJson<{ data: PayrollBreakdown }>("/api/v1/analytics/breakdown", params, signal).then(
    (body) => body.data,
  );
}

export function usePayrollSummary(params: AnalyticsParams) {
  // The dimension is dropped rather than sent. The summary does not group by
  // anything, so including it would make the cache key change — and the totals
  // refetch — every time someone switches the chart below them.
  const { dimension: _dimension, ...rest } = params;

  return useQuery({
    queryKey: ["analytics", "summary", rest],
    queryFn: ({ signal }) => fetchSummary(rest, signal),
    // A total that blanks and returns reads as a total that changed. Holding
    // the previous figures while the next ones arrive keeps the page still.
    placeholderData: keepPreviousData,
  });
}

export function usePayrollBreakdown(params: AnalyticsParams) {
  return useQuery({
    queryKey: ["analytics", "breakdown", params],
    queryFn: ({ signal }) => fetchBreakdown(params, signal),
    placeholderData: keepPreviousData,
  });
}
