import { useCallback, useMemo } from "react";
import { useSearchParams } from "react-router-dom";
import type { BreakdownDimension } from "../api/types";
import type { AnalyticsParams } from "./api";

const DIMENSIONS: BreakdownDimension[] = ["country", "department", "job_level"];
const DEFAULT_DIMENSION: BreakdownDimension = "department";

/**
 * The dashboard's state lives in the URL, for the same reason the directory's
 * does: the next thing someone does with a payroll figure is send it to
 * somebody, and a number without the filters that produced it is not an answer.
 * "Total cost of Engineering in Poland as of January" has to survive being
 * pasted into a message.
 */
export function useAnalyticsParams() {
  const [searchParams, setSearchParams] = useSearchParams();

  const params = useMemo<AnalyticsParams>(() => fromSearchParams(searchParams), [searchParams]);

  const update = useCallback(
    (patch: Partial<AnalyticsParams>) => {
      setSearchParams((current) => toSearchParams({ ...fromSearchParams(current), ...patch }), {
        // Changing a filter is not navigation; the back button should leave the
        // page rather than walk back through every adjustment.
        replace: true,
      });
    },
    [setSearchParams],
  );

  const clear = useCallback(() => setSearchParams({}, { replace: true }), [setSearchParams]);

  return { params, update, clear };
}

export function fromSearchParams(search: URLSearchParams): AnalyticsParams {
  return {
    q: search.get("q") ?? "",
    // Left empty rather than filled with today's date. The server already
    // defaults to today, and writing it in would freeze a shared link to the
    // day it was sent — so a colleague opening it next month would see stale
    // figures presented as current ones.
    as_of: search.get("as_of") ?? "",
    dimension: asDimension(search.get("dimension")),
    country_code: search.getAll("country_code"),
    department_id: search.getAll("department_id").map(Number).filter(Number.isInteger),
    job_level: search.getAll("job_level"),
  };
}

function toSearchParams(params: AnalyticsParams): URLSearchParams {
  const search = new URLSearchParams();

  if (params.q) search.set("q", params.q);
  if (params.as_of) search.set("as_of", params.as_of);
  if (params.dimension && params.dimension !== DEFAULT_DIMENSION) {
    search.set("dimension", params.dimension);
  }

  for (const code of params.country_code ?? []) search.append("country_code", code);
  for (const id of params.department_id ?? []) search.append("department_id", String(id));
  for (const level of params.job_level ?? []) search.append("job_level", String(level));

  return search;
}

/**
 * An unrecognised dimension is a URL someone edited or a link that rotted. The
 * server would ignore it and answer by department anyway; agreeing with it here
 * keeps the segmented control from showing nothing selected while the chart
 * below it is plainly grouped by something.
 */
function asDimension(value: string | null): BreakdownDimension {
  const match = DIMENSIONS.find((dimension) => dimension === value);

  return match ?? DEFAULT_DIMENSION;
}

export { DIMENSIONS, DEFAULT_DIMENSION };
