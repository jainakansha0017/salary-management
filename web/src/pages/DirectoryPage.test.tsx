import { afterEach, describe, expect, it, vi } from "vitest";
import { screen } from "@testing-library/react";
import { DirectoryPage } from "./DirectoryPage";
import { renderWithProviders, stubFetch } from "../test/harness";
import type { EmployeeSummary, Paginated } from "../api/types";

afterEach(() => vi.unstubAllGlobals());

function employee(overrides: Partial<EmployeeSummary> = {}): EmployeeSummary {
  return {
    id: 1,
    employee_number: "ACME-00001",
    full_name: "Anna Kowalski",
    email: "anna.kowalski@acme.example",
    country_code: "PL",
    department: "Engineering",
    job_title: "Staff Engineer",
    job_level: "L5",
    hired_on: "2021-03-01",
    ended_on: null,
    active: true,
    current_salary: {
      amount: { amount_minor: 17_260_000, currency_code: "PLN", minor_unit: 2 },
      base_amount: { amount_minor: 4_401_300, currency_code: "USD", minor_unit: 2 },
      effective_from: "2025-08-16",
    },
    ...overrides,
  };
}

function page(employees: EmployeeSummary[]): Paginated<EmployeeSummary> {
  return {
    data: employees,
    meta: {
      page: 1,
      page_size: 25,
      total_count: employees.length,
      total_pages: 1,
      applied: { search: "", country_code: [], department_id: [], job_level: [] },
    },
  };
}

function stubDirectory(body: unknown, status?: number) {
  return stubFetch({ "/api/v1/employees": { body, ...(status ? { status } : {}) } });
}

describe("the employee directory", () => {
  it("shows pay in the currency it is paid in, and in the base currency beside it", async () => {
    stubDirectory(page([employee()]));

    renderWithProviders(<DirectoryPage />);

    expect(await screen.findByText("Anna Kowalski")).toBeInTheDocument();
    // Both figures, because "what is she paid" and "how does she compare" are
    // different questions and the page is asked both.
    //
    // A plain space, unlike the unit test in format.test.ts: Testing Library
    // normalises the non-breaking space out of the DOM text before matching.
    expect(screen.getByText("PLN 172,600.00")).toBeInTheDocument();
    expect(screen.getByText("$44,013.00")).toBeInTheDocument();
  });

  it("reports how many people matched, not just how many are on screen", async () => {
    const body = page([employee()]);
    body.meta.total_count = 9565;
    stubDirectory(body);

    renderWithProviders(<DirectoryPage />);

    expect(await screen.findByText("9,565 employees")).toBeInTheDocument();
  });

  // A leaver has no salary in effect. Rendering that as a blank cell is
  // indistinguishable from a rendering fault, and as $0.00 it is a lie.
  it("marks absent pay rather than showing a blank or a zero", async () => {
    stubDirectory(page([employee({ active: false, ended_on: "2025-12-07", current_salary: null })]));

    renderWithProviders(<DirectoryPage />);

    await screen.findByText("Anna Kowalski");
    expect(screen.getAllByText("—")).toHaveLength(2);
    expect(screen.queryByText("$0.00")).not.toBeInTheDocument();
  });

  it("says so when nobody matches, instead of showing an empty table", async () => {
    stubDirectory(page([]));

    renderWithProviders(<DirectoryPage />);

    expect(await screen.findByText(/nothing matches/i)).toBeInTheDocument();
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
  });

  // The failure mode this guards: a 500 rendering as an empty table, which
  // reads as "there are no employees".
  it("shows the server's own message when the request fails", async () => {
    stubDirectory({ error: { code: "invalid_parameter", message: "dimension must be one of: country" } }, 400);

    renderWithProviders(<DirectoryPage />);

    expect(await screen.findByRole("alert")).toHaveTextContent("dimension must be one of: country");
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
  });
});
