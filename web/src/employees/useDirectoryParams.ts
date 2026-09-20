import { useCallback, useMemo } from "react";
import { useSearchParams } from "react-router-dom";
import type { DirectoryParams } from "./api";

/**
 * The directory's state lives in the URL, not in React.
 *
 * An HR manager's usual next move after filtering is to send someone the
 * result — "here is everyone in Engineering in Poland". Keeping the filters in
 * component state would make that link mean something different for the person
 * who opens it, and would break the back button in a UI whose whole purpose is
 * narrowing and widening a search. It also means a reload does not throw the
 * work away.
 *
 * The API's bracketed array form (`country_code[]=PL`) is not used here. That
 * is a Rails wire detail, applied by the fetch client; a URL a person might
 * read or edit uses plain repeated keys.
 */
export function useDirectoryParams() {
  const [searchParams, setSearchParams] = useSearchParams();

  const params = useMemo<DirectoryParams>(() => fromSearchParams(searchParams), [searchParams]);

  /**
   * Any change to what is being asked returns to page one. Staying on page 40
   * while narrowing to a group of twelve shows an empty table, which reads as
   * "nobody matches" when the truth is "not on this page".
   */
  const update = useCallback(
    (patch: Partial<DirectoryParams>) => {
      setSearchParams(
        (current) => toSearchParams({ ...fromSearchParams(current), page: 1, ...patch }),
        // Filtering is not navigation. Without this, narrowing a search five
        // times puts five entries in the history and the back button becomes
        // useless for leaving the page.
        { replace: true },
      );
    },
    [setSearchParams],
  );

  /** Paging *is* navigation, so it keeps its history entry. */
  const goToPage = useCallback(
    (page: number) => {
      setSearchParams((current) => toSearchParams({ ...fromSearchParams(current), page }));
    },
    [setSearchParams],
  );

  const clear = useCallback(() => setSearchParams({}, { replace: true }), [setSearchParams]);

  return { params, update, goToPage, clear };
}

/**
 * Sorting by a column already on screen should not also change what is on
 * screen, so a second click reverses the existing direction rather than
 * resetting to ascending. A new column starts in the direction that answers the
 * question being asked: pay and hire date are interesting from the top.
 */
export function nextSort(
  current: DirectoryParams,
  column: string,
): Pick<DirectoryParams, "sort" | "direction"> {
  if (current.sort === column) {
    return {
      sort: column,
      direction: current.direction === "desc" ? "asc" : "desc",
    };
  }

  return {
    sort: column,
    direction: DESCENDING_FIRST.has(column) ? "desc" : "asc",
  };
}

const DESCENDING_FIRST = new Set(["salary", "hired_on"]);

export function fromSearchParams(search: URLSearchParams): DirectoryParams {
  const page = Number(search.get("page"));
  const sort = search.get("sort") ?? "name";

  return {
    q: search.get("q") ?? "",
    status: search.get("status") ?? "active",
    sort,
    // The column's own default, not a blanket "asc" — `toSearchParams` leaves
    // the default out of the URL, so `?sort=salary` has to read back as the
    // descending sort that produced it.
    direction: search.get("direction") ?? defaultDirectionFor(sort),
    // A page of "0", "-3" or "banana" is a URL someone edited or a link that
    // rotted. Falling back to the first page shows them something.
    page: Number.isInteger(page) && page > 0 ? page : 1,
    country_code: search.getAll("country_code"),
    department_id: search.getAll("department_id").map(Number).filter(Number.isInteger),
    job_level: search.getAll("job_level"),
  };
}

/**
 * Defaults are left out of the URL. `?sort=name&direction=asc&status=active` is
 * three parameters saying "no preference expressed", and they would be carried
 * into every link that gets shared.
 */
function toSearchParams(params: DirectoryParams): URLSearchParams {
  const search = new URLSearchParams();

  if (params.q) search.set("q", params.q);
  if (params.status && params.status !== "active") search.set("status", params.status);
  if (params.sort && params.sort !== "name") search.set("sort", params.sort);
  if (params.direction && params.direction !== defaultDirectionFor(params.sort)) {
    search.set("direction", params.direction);
  }
  if (params.page && params.page > 1) search.set("page", String(params.page));

  for (const code of params.country_code ?? []) search.append("country_code", code);
  for (const id of params.department_id ?? []) search.append("department_id", String(id));
  for (const level of params.job_level ?? []) search.append("job_level", String(level));

  return search;
}

function defaultDirectionFor(sort: string | undefined): string {
  return sort && DESCENDING_FIRST.has(sort) ? "desc" : "asc";
}
