import type { ApiErrorBody } from "./types";

/**
 * Empty by default, because `vite.config.ts` proxies `/api` in development and
 * the two are deployed behind one origin. Set `VITE_API_BASE_URL` when they are
 * not, which is the only case that needs CORS on the Rails side.
 */
const BASE_URL = import.meta.env["VITE_API_BASE_URL"] ?? "";

/**
 * A failed request, carrying what the API said about it rather than only a
 * status code. `details` is what lets a form mark the field that was wrong
 * instead of showing one message above everything.
 */
export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly details: Record<string, string[]>;

  constructor(status: number, body: Partial<ApiErrorBody>) {
    super(body.message ?? `Request failed with status ${status}`);
    this.name = "ApiError";
    this.status = status;
    this.code = body.code ?? "unknown_error";
    this.details = body.details ?? {};
  }
}

/**
 * `object` rather than `Record<string, unknown>`, so that a caller can pass a
 * precisely typed parameter object — `DirectoryParams`, say — and keep the
 * compiler checking it for typos, which an index signature would switch off.
 */
export type QueryParams = object;

/**
 * Built by hand rather than with a query-string library. `URLSearchParams`
 * already appends repeated keys as `country_code[]=PL&country_code[]=DE`, which
 * is exactly the bracketed form Rails' `permit(country_code: [])` expects — and
 * it escapes values, so a search term containing `&` cannot become a second
 * parameter.
 */
export function toQuery(params: QueryParams): string {
  const search = new URLSearchParams();

  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null || value === "") continue;

    if (Array.isArray(value)) {
      for (const entry of value) search.append(`${key}[]`, String(entry));
    } else {
      search.append(key, String(value));
    }
  }

  const query = search.toString();
  return query ? `?${query}` : "";
}

export function apiUrl(path: string, params: QueryParams = {}): string {
  return `${BASE_URL}${path}${toQuery(params)}`;
}

export async function getJson<T>(
  path: string,
  params: QueryParams = {},
  signal?: AbortSignal,
): Promise<T> {
  const response = await fetch(apiUrl(path, params), {
    headers: { Accept: "application/json" },
    ...(signal ? { signal } : {}),
  });

  return unwrap<T>(response);
}

export async function postJson<T>(path: string, body: unknown): Promise<T> {
  const response = await fetch(apiUrl(path), {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify(body),
  });

  return unwrap<T>(response);
}

/**
 * A non-2xx response still has a body worth reading — that is where the field
 * errors are. A body that will not parse is treated as no body rather than
 * being allowed to throw a `SyntaxError`, which would hide the status behind a
 * misleading message.
 */
async function unwrap<T>(response: Response): Promise<T> {
  const payload = await parseBody(response);

  if (!response.ok) {
    const error = (payload as { error?: Partial<ApiErrorBody> } | null)?.error;
    throw new ApiError(response.status, error ?? {});
  }

  return payload as T;
}

async function parseBody(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    return null;
  }
}
