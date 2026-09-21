import { afterEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AnalyticsPage } from "./AnalyticsPage";
import { renderWithProviders, stubFetch } from "../test/harness";
import type {
  BreakdownGroup,
  DirectoryFacets,
  Money,
  PayrollBreakdown,
  PayrollSummary,
} from "../api/types";

afterEach(() => vi.unstubAllGlobals());

function usd(amount_minor: number): Money {
  return { amount_minor, currency_code: "USD", minor_unit: 2 };
}

const SUMMARY: PayrollSummary = {
  headcount: 9565,
  total: usd(88_577_614_638),
  average: usd(9_260_597),
  minimum: usd(930_810),
  maximum: usd(41_310_000),
  percentiles: {
    p10: usd(2_784_132),
    p25: usd(4_565_700),
    median: usd(7_950_000),
    p75: usd(12_230_000),
    p90: usd(17_580_120),
  },
  distribution: [
    { from: usd(0), to: usd(5_000_000), headcount: 2713 },
    { from: usd(5_000_000), to: usd(10_000_000), headcount: 3340 },
    { from: usd(40_000_000), to: usd(45_000_000), headcount: 4 },
  ],
};

function group(overrides: Partial<BreakdownGroup> = {}): BreakdownGroup {
  return {
    key: 11,
    label: "Engineering",
    headcount: 941,
    total: usd(10_111_413_260),
    average: usd(10_745_391),
    percentiles: { p25: usd(5_452_200), median: usd(9_120_000), p75: usd(14_270_000) },
    ...overrides,
  };
}

const BREAKDOWN: PayrollBreakdown = {
  dimension: "department",
  groups: [group(), group({ key: 12, label: "Data", headcount: 944 })],
};

const FACETS: DirectoryFacets = {
  countries: ["IN", "PL"],
  departments: [{ id: 11, name: "Engineering" }],
  job_levels: ["L3", "L5"],
};

function stubAnalytics(breakdown: PayrollBreakdown = BREAKDOWN) {
  return stubFetch({
    "/api/v1/filters": { body: { data: FACETS } },
    "/api/v1/analytics/summary": { body: { data: SUMMARY } },
    "/api/v1/analytics/breakdown": { body: { data: breakdown } },
  });
}

/** The most recent breakdown request, which is what the lower table shows. */
function lastBreakdownCall(calls: string[]): string {
  const matching = calls.filter((url) => url.includes("/analytics/breakdown"));
  return matching[matching.length - 1] ?? "";
}

function lastSummaryCall(calls: string[]): string {
  const matching = calls.filter((url) => url.includes("/analytics/summary"));
  return matching[matching.length - 1] ?? "";
}

describe("the payroll dashboard", () => {
  it("leads with what the organisation costs", async () => {
    stubAnalytics();
    renderWithProviders(<AnalyticsPage />, { route: "/analytics" });

    expect(await screen.findByText("$885,776,146.38")).toBeInTheDocument();
    expect(screen.getByText("9,565")).toBeInTheDocument();
  });

  // The gap between the two is the first thing worth noticing: where it is
  // wide, the average is being pulled by a few large salaries.
  it("puts the median beside the average rather than only the average", async () => {
    stubAnalytics();
    renderWithProviders(<AnalyticsPage />, { route: "/analytics" });

    // Scoped: "Median" also labels a percentile below and a table column
    // further down, and an unscoped query would not say which was asserted.
    const totals = within(await screen.findByRole("region", { name: "Payroll totals" }));
    expect(totals.getByText("Median").nextElementSibling).toHaveTextContent("$79,500.00");
    expect(totals.getByText("Average").nextElementSibling).toHaveTextContent("$92,605.97");
  });

  it("shows the long tail as a share rather than rounding it away", async () => {
    stubAnalytics();
    renderWithProviders(<AnalyticsPage />, { route: "/analytics" });

    // Four people out of 6,057 in the seeded bands is 0.1%, not 0%.
    const tail = (await screen.findByText("$400K – $450K")).closest("tr");
    expect(within(tail!).getByText("0.1%")).toBeInTheDocument();
  });

  it("asks about today unless a date is given", async () => {
    const { calls } = stubAnalytics();
    renderWithProviders(<AnalyticsPage />, { route: "/analytics" });

    await screen.findByText("$885,776,146.38");
    expect(lastSummaryCall(calls)).not.toContain("as_of");
    expect(screen.getByText("As of today")).toBeInTheDocument();
  });

  it("asks about the date in the URL when there is one", async () => {
    const { calls } = stubAnalytics();
    renderWithProviders(<AnalyticsPage />, { route: "/analytics?as_of=2026-01-31" });

    await screen.findByText("$885,776,146.38");
    expect(lastSummaryCall(calls)).toContain("as_of=2026-01-31");
    expect(screen.getByText("As of Jan 31, 2026")).toBeInTheDocument();
  });

  it("narrows both halves of the page with one filter", async () => {
    const { calls } = stubAnalytics();
    renderWithProviders(<AnalyticsPage />, { route: "/analytics?country_code=PL" });

    await screen.findByText("$885,776,146.38");
    expect(lastSummaryCall(calls)).toContain("country_code%5B%5D=PL");
    expect(lastBreakdownCall(calls)).toContain("country_code%5B%5D=PL");
  });
});

describe("comparing groups", () => {
  it("shows the middle half, not only the average", async () => {
    stubAnalytics();
    renderWithProviders(<AnalyticsPage />, { route: "/analytics" });

    // By cell, not by text: "Engineering" is also an option in the department
    // filter above, and that one has no row to read figures from.
    const row = (await screen.findByRole("cell", { name: "Engineering" })).closest("tr");
    expect(within(row!).getByText("$107,453.91")).toBeInTheDocument();
    expect(within(row!).getByText("$54.5K – $142.7K")).toBeInTheDocument();
  });

  it("regroups on the server rather than in the browser", async () => {
    const { calls } = stubAnalytics();
    renderWithProviders(<AnalyticsPage />, { route: "/analytics" });

    await screen.findByRole("cell", { name: "Engineering" });
    await userEvent.click(screen.getByRole("radio", { name: "Country" }));

    await waitFor(() => expect(lastBreakdownCall(calls)).toContain("dimension=country"));
  });

  // The summary does not group by anything, so switching the chart below it
  // must not make the headline totals refetch and flicker.
  it("does not re-ask for the totals when only the grouping changes", async () => {
    const { calls } = stubAnalytics();
    renderWithProviders(<AnalyticsPage />, { route: "/analytics" });

    await screen.findByRole("cell", { name: "Engineering" });
    const before = calls.filter((url) => url.includes("/analytics/summary")).length;

    await userEvent.click(screen.getByRole("radio", { name: "Country" }));
    await waitFor(() => expect(lastBreakdownCall(calls)).toContain("dimension=country"));

    expect(calls.filter((url) => url.includes("/analytics/summary"))).toHaveLength(before);
  });

  // A level means different money in different countries, so the comparison is
  // confounded unless the reader knows that. Saying so is cheaper, and more
  // honest, than a number that looks authoritative and is not.
  it("warns that levels are not comparable across countries", async () => {
    stubAnalytics({ dimension: "job_level", groups: [group({ key: "L5", label: "L5" })] });
    renderWithProviders(<AnalyticsPage />, { route: "/analytics?dimension=job_level" });

    expect(await screen.findByText(/An L5 in India is paid less than an L3/)).toBeInTheDocument();
  });

  it("carries that warning only where it applies", async () => {
    stubAnalytics();
    renderWithProviders(<AnalyticsPage />, { route: "/analytics" });

    await screen.findByRole("cell", { name: "Engineering" });
    expect(screen.queryByText(/not comparable across countries/)).not.toBeInTheDocument();
  });
});
