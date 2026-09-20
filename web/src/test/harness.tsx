import type { ReactElement } from "react";
import { render } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { vi } from "vitest";
import { ROUTER_FUTURE } from "../router-future";

/**
 * Renders a component with the providers it would have in the application.
 *
 * A fresh `QueryClient` per test, because a cache shared between tests makes
 * one test pass on another's data. Retries are off so that a test asserting an
 * error state fails in milliseconds rather than after a backoff.
 */
export function renderWithProviders(ui: ReactElement, { route = "/" }: { route?: string } = {}) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, gcTime: 0 } },
  });

  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={[route]} future={ROUTER_FUTURE}>
        {ui}
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

/**
 * Stubs `fetch` with a lookup from URL substring to response.
 *
 * Deliberately not a mock of our own client: a test that stubs `getJson` proves
 * the component calls a function, whereas this one goes through the real URL
 * building, the real status handling and the real error shape — which is where
 * the mistakes actually are. It records the URLs so a test can assert what was
 * asked for.
 */
export interface RecordedRequest {
  url: string;
  method: string;
  /** The parsed JSON body, for asserting what a form actually sent. */
  body: unknown;
}

export function stubFetch(routes: Record<string, { status?: number; body: unknown }>) {
  const calls: string[] = [];
  const requests: RecordedRequest[] = [];

  const fetchStub = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    calls.push(url);
    requests.push({ url, method: init?.method ?? "GET", body: parse(init?.body) });

    const match = Object.keys(routes).find((pattern) => url.includes(pattern));
    const route = match ? routes[match] : undefined;

    if (!route) {
      throw new Error(`No stubbed response for ${url}`);
    }

    const status = route.status ?? 200;
    return new Response(JSON.stringify(route.body), {
      status,
      headers: { "Content-Type": "application/json" },
    });
  });

  vi.stubGlobal("fetch", fetchStub);

  return { calls, requests };
}

function parse(body: BodyInit | null | undefined): unknown {
  if (typeof body !== "string") return undefined;

  try {
    return JSON.parse(body);
  } catch {
    return body;
  }
}
