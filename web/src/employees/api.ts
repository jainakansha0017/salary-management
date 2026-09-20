import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { apiUrl, getJson, postJson } from "../api/client";
import type {
  Compensation,
  CompensationReason,
  DirectoryFacets,
  EmployeeDetail,
  EmployeeSummary,
  Paginated,
} from "../api/types";

/**
 * Exactly the parameters the Rails `EmployeeDirectoryQuery` understands. Kept
 * as one object because it is also the cache key and the export's query string:
 * three things that must describe the same request, so they are built from the
 * same value.
 */
export interface DirectoryParams {
  q?: string;
  status?: string;
  sort?: string;
  direction?: string;
  page?: number;
  page_size?: number;
  country_code?: string[];
  department_id?: number[];
  job_level?: string[];
}

const DIRECTORY_PATH = "/api/v1/employees";

export function useDirectory(params: DirectoryParams) {
  return useQuery({
    queryKey: ["employees", params],
    queryFn: ({ signal }) => getJson<Paginated<EmployeeSummary>>(DIRECTORY_PATH, params, signal),
    // Without this the table unmounts to a spinner on every keystroke, and the
    // page jumps as the layout collapses and reopens. Holding the previous
    // result keeps the rows in place while the next ones are on their way.
    placeholderData: keepPreviousData,
  });
}

/**
 * The filter panel's options. Countries, departments and levels change when the
 * organisation does, not while someone is looking at a page, so this is cached
 * for the session rather than refetched alongside every directory request.
 */
export function useDirectoryFacets() {
  return useQuery({
    queryKey: ["filters"],
    queryFn: ({ signal }) =>
      getJson<{ data: DirectoryFacets }>("/api/v1/filters", {}, signal).then((body) => body.data),
    staleTime: Infinity,
  });
}

export function useEmployee(id: string) {
  return useQuery({
    queryKey: ["employee", id],
    queryFn: ({ signal }) =>
      getJson<{ data: EmployeeDetail }>(`${DIRECTORY_PATH}/${id}`, {}, signal).then(
        (body) => body.data,
      ),
  });
}

/** Exactly what `SalaryChangeForm` permits on the Rails side. */
export interface SalaryChangeInput {
  amount_minor: number;
  currency_code: string;
  effective_from: string;
  reason: CompensationReason;
  note?: string;
}

/**
 * Recording a change invalidates rather than writes to the cache.
 *
 * The response is the new period alone, but the write also closed the previous
 * one and may have moved the figure the directory shows — so the server's
 * version of both is refetched instead of this client reconstructing what it
 * thinks happened.
 */
export function useRecordSalaryChange(id: string) {
  const client = useQueryClient();

  return useMutation({
    mutationFn: (input: SalaryChangeInput) =>
      postJson<{ data: Compensation }>(`${DIRECTORY_PATH}/${id}/salary_changes`, {
        salary_change: input,
      }),
    onSuccess: () => {
      void client.invalidateQueries({ queryKey: ["employee", id] });
      void client.invalidateQueries({ queryKey: ["employees"] });
    },
  });
}

/**
 * A plain link rather than a fetch: letting the browser do the download means
 * no blob in memory, a real progress indicator, and a `Content-Disposition`
 * filename that is honoured. The parameters are the ones on screen, so the file
 * holds the list the user is looking at.
 */
export function directoryExportUrl(params: DirectoryParams): string {
  const { page: _page, page_size: _pageSize, ...rest } = params;

  return apiUrl(`${DIRECTORY_PATH}.csv`, rest);
}
