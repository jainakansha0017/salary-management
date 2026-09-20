import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { App } from "./App";
import { ROUTER_FUTURE } from "./router-future";
import "./styles.css";

/**
 * Salary data changes when someone records a change, not on a timer, so the
 * aggressive defaults are turned off: refetching the directory because the
 * window regained focus would reorder a table under someone's cursor for no
 * new information.
 *
 * `staleTime` is what makes paging back and forth instant, and what stops a
 * filter being re-requested when nothing about it moved.
 */
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      refetchOnWindowFocus: false,
      // One retry, for a dropped connection. More than that turns a 500 into a
      // long wait before the user is told anything.
      retry: 1,
    },
  },
});

const container = document.getElementById("root");
if (!container) throw new Error("No #root element to mount into");

createRoot(container).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <BrowserRouter future={ROUTER_FUTURE}>
        <App />
      </BrowserRouter>
    </QueryClientProvider>
  </StrictMode>,
);
