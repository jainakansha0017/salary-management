import type { ReactNode } from "react";
import type { UseQueryResult } from "@tanstack/react-query";
import { ApiError } from "../api/client";

interface Props<T> {
  query: UseQueryResult<T>;
  children: (data: T) => ReactNode;
  /** What "nothing to show" means for this data, which only the caller knows. */
  emptyWhen?: (data: T) => boolean;
  emptyMessage?: string;
}

/**
 * The three states every fetch has, in one place.
 *
 * Written once because getting them wrong is the usual way a data-heavy page
 * misleads someone: an empty table that is actually still loading reads as "no
 * such employees", and a failed request that renders as an empty table reads
 * the same way. Here the three are mutually exclusive and each says which it
 * is.
 */
export function QueryState<T>({ query, children, emptyWhen, emptyMessage }: Props<T>) {
  if (query.isPending) {
    return <p className="state state--pending">Loading…</p>;
  }

  if (query.isError) {
    return <Failure error={query.error} onRetry={() => void query.refetch()} />;
  }

  if (emptyWhen?.(query.data)) {
    return <p className="state state--empty">{emptyMessage ?? "Nothing matches."}</p>;
  }

  return (
    <>
      {/* The data is already on screen during a refetch, so this is a quiet
          marker rather than a spinner replacing the table. */}
      {query.isFetching && (
        <span className="state state--refetching" role="status">
          Updating…
        </span>
      )}
      {children(query.data)}
    </>
  );
}

function Failure({ error, onRetry }: { error: unknown; onRetry: () => void }) {
  return (
    <div className="state state--error" role="alert">
      <p className="state__message">{messageFor(error)}</p>
      <button type="button" className="button" onClick={onRetry}>
        Try again
      </button>
    </div>
  );
}

/**
 * The API's own message when there is one — it is written to be read by a
 * person — and a plain sentence otherwise. Never the raw exception, which for
 * a network failure is "Failed to fetch".
 */
function messageFor(error: unknown): string {
  if (error instanceof ApiError) return error.message;

  return "Could not reach the server.";
}
