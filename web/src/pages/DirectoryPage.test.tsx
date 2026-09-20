import { afterEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { DirectoryPage } from "./DirectoryPage";
import { renderWithProviders, stubFetch } from "../test/harness";
import type { DirectoryFacets, EmployeeSummary, Paginated } from "../api/types";

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
      base_amount: {
        amount_minor: 4_401_300,
        currency_code: "USD",
        minor_unit: 2,
      },
      effective_from: "2025-08-16",
    },
    ...overrides,
  };
}

function page(
  employees: EmployeeSummary[],
  meta: Partial<Paginated<EmployeeSummary>["meta"]> = {},
): Paginated<EmployeeSummary> {
  return {
    data: employees,
    meta: {
      page: 1,
      page_size: 25,
      total_count: employees.length,
      total_pages: 1,
      applied: {
        search: "",
        country_code: [],
        department_id: [],
        job_level: [],
      },
      ...meta,
    },
  };
}

const FACETS: DirectoryFacets = {
  countries: ["IN", "PL"],
  departments: [
    { id: 11, name: "Engineering" },
    { id: 14, name: "Design" },
  ],
  job_levels: ["L4", "L5"],
};

function stubDirectory(body: unknown, status?: number) {
  return stubFetch({
    "/api/v1/filters": { body: { data: FACETS } },
    "/api/v1/employees": { body, ...(status ? { status } : {}) },
  });
}

/** The most recent directory request, which is what the table is showing. */
function lastDirectoryCall(calls: string[]): string {
  const directory = calls.filter((url) => url.includes("/api/v1/employees"));
  return directory[directory.length - 1] ?? "";
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
    stubDirectory(page([employee()], { total_count: 9565, total_pages: 383 }));

    renderWithProviders(<DirectoryPage />);

    expect(await screen.findByText("9,565 employees")).toBeInTheDocument();
  });

  // A leaver has no salary in effect. Rendering that as a blank cell is
  // indistinguishable from a rendering fault, and as $0.00 it is a lie.
  it("marks absent pay rather than showing a blank or a zero", async () => {
    stubDirectory(
      page([
        employee({
          active: false,
          ended_on: "2025-12-07",
          current_salary: null,
        }),
      ]),
    );

    renderWithProviders(<DirectoryPage />);

    await screen.findByText("Anna Kowalski");
    expect(screen.getAllByText("—")).toHaveLength(2);
    expect(screen.queryByText("$0.00")).not.toBeInTheDocument();
  });

  it("says so when nobody matches, instead of showing an empty table", async () => {
    stubDirectory(page([]));

    renderWithProviders(<DirectoryPage />);

    expect(await screen.findByText(/nobody matches/i)).toBeInTheDocument();
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
  });

  // The failure mode this guards: a 500 rendering as an empty table, which
  // reads as "there are no employees".
  it("shows the server's own message when the request fails", async () => {
    stubDirectory(
      {
        error: {
          code: "invalid_parameter",
          message: "dimension must be one of: country",
        },
      },
      400,
    );

    renderWithProviders(<DirectoryPage />);

    expect(await screen.findByRole("alert")).toHaveTextContent("dimension must be one of: country");
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
  });
});

describe("narrowing the directory", () => {
  it("asks the server for the search term once the typing stops", async () => {
    const user = userEvent.setup();
    const { calls } = stubDirectory(page([employee()]));

    renderWithProviders(<DirectoryPage />);
    await screen.findByText("Anna Kowalski");

    await user.type(screen.getByLabelText("Search"), "kowalski");

    await waitFor(() => expect(lastDirectoryCall(calls)).toContain("q=kowalski"));

    // The point of the debounce: eight keystrokes are not eight requests.
    expect(calls.filter((url) => url.includes("q=")).length).toBeLessThan(8);
  });

  it("sends a chosen facet in the bracketed form Rails expects", async () => {
    const user = userEvent.setup();
    const { calls } = stubDirectory(page([employee()]));

    renderWithProviders(<DirectoryPage />);
    await screen.findByText("Anna Kowalski");

    await user.selectOptions(await screen.findByLabelText(/Country/), "PL");

    await waitFor(() => expect(lastDirectoryCall(calls)).toContain("country_code%5B%5D=PL"));
  });

  // Department ids come from the server for exactly this reason: the filter has
  // to send 11, not "Engineering".
  it("filters departments by id rather than by name", async () => {
    const user = userEvent.setup();
    const { calls } = stubDirectory(page([employee()]));

    renderWithProviders(<DirectoryPage />);
    await screen.findByText("Anna Kowalski");

    await user.selectOptions(await screen.findByLabelText(/Department/), "11");

    await waitFor(() => expect(lastDirectoryCall(calls)).toContain("department_id%5B%5D=11"));
    expect(lastDirectoryCall(calls)).not.toContain("Engineering");
  });

  it("offers a way back out once something is filtered", async () => {
    const user = userEvent.setup();
    const { calls } = stubDirectory(page([employee()]));

    renderWithProviders(<DirectoryPage />);
    await screen.findByText("Anna Kowalski");

    expect(screen.queryByRole("button", { name: /clear all/i })).not.toBeInTheDocument();

    await user.selectOptions(await screen.findByLabelText(/Country/), "PL");
    await user.click(await screen.findByRole("button", { name: /clear all/i }));

    await waitFor(() => expect(lastDirectoryCall(calls)).not.toContain("country_code"));
  });
});

describe("sorting the directory", () => {
  it("sorts pay from the top on the first click, because nobody asks who earns least", async () => {
    const user = userEvent.setup();
    const { calls } = stubDirectory(page([employee()]));

    renderWithProviders(<DirectoryPage />);
    await screen.findByText("Anna Kowalski");

    await user.click(screen.getByRole("button", { name: /^Salary/ }));

    await waitFor(() => expect(lastDirectoryCall(calls)).toContain("sort=salary"));
    expect(lastDirectoryCall(calls)).toContain("direction=desc");
  });

  it("reverses rather than resetting when the same column is clicked again", async () => {
    const user = userEvent.setup();
    const { calls } = stubDirectory(page([employee()]));

    renderWithProviders(<DirectoryPage />);
    await screen.findByText("Anna Kowalski");

    const salary = screen.getByRole("button", { name: /^Salary/ });
    await user.click(salary);
    await waitFor(() => expect(lastDirectoryCall(calls)).toContain("direction=desc"));

    await user.click(salary);
    await waitFor(() => expect(lastDirectoryCall(calls)).toContain("direction=asc"));
  });

  // Without this a screen reader is told the table is sorted by name while it
  // is sorted by pay.
  it("tells assistive technology which column is sorted and which way", async () => {
    const user = userEvent.setup();
    stubDirectory(page([employee()]));

    renderWithProviders(<DirectoryPage />);
    await screen.findByText("Anna Kowalski");

    expect(screen.getByRole("columnheader", { name: /Employee/ })).toHaveAttribute(
      "aria-sort",
      "ascending",
    );

    await user.click(screen.getByRole("button", { name: /^Salary/ }));

    await waitFor(() =>
      expect(screen.getByRole("columnheader", { name: /^Salary/ })).toHaveAttribute(
        "aria-sort",
        "descending",
      ),
    );
    expect(screen.getByRole("columnheader", { name: /Employee/ })).toHaveAttribute(
      "aria-sort",
      "none",
    );
  });
});

describe("paging through the directory", () => {
  it("says which rows are on screen, not only which page", async () => {
    stubDirectory(page([employee()], { page: 3, total_count: 9565, total_pages: 383 }));

    renderWithProviders(<DirectoryPage />, { route: "/employees?page=3" });

    expect(await screen.findByText("51–75 of 9,565")).toBeInTheDocument();
  });

  it("cannot be paged off either end", async () => {
    stubDirectory(page([employee()], { page: 1, total_count: 1, total_pages: 1 }));

    renderWithProviders(<DirectoryPage />);
    await screen.findByText("Anna Kowalski");

    const pagination = screen.getByRole("navigation", { name: /pagination/i });
    expect(within(pagination).getByRole("button", { name: /previous/i })).toBeDisabled();
    expect(within(pagination).getByRole("button", { name: /next/i })).toBeDisabled();
  });

  it("asks for the next page when told to", async () => {
    const user = userEvent.setup();
    const { calls } = stubDirectory(
      page([employee()], { page: 1, total_count: 9565, total_pages: 383 }),
    );

    renderWithProviders(<DirectoryPage />);
    await screen.findByText("Anna Kowalski");

    await user.click(screen.getByRole("button", { name: /next/i }));

    await waitFor(() => expect(lastDirectoryCall(calls)).toContain("page=2"));
  });

  // Narrowing to twelve people while on page 40 would otherwise show an empty
  // table, which reads as "nobody matches" when the truth is "not on this page".
  it("returns to the first page when the filters change", async () => {
    const user = userEvent.setup();
    const { calls } = stubDirectory(
      page([employee()], { page: 4, total_count: 9565, total_pages: 383 }),
    );

    renderWithProviders(<DirectoryPage />, { route: "/employees?page=4" });
    await screen.findByText("Anna Kowalski");

    await user.selectOptions(await screen.findByLabelText(/Country/), "PL");

    await waitFor(() => expect(lastDirectoryCall(calls)).toContain("country_code"));
    expect(lastDirectoryCall(calls)).not.toContain("page=4");
  });
});

describe("exporting what is on screen", () => {
  it("downloads the filtered list rather than everyone", async () => {
    const user = userEvent.setup();
    stubDirectory(page([employee()]));

    renderWithProviders(<DirectoryPage />);
    await screen.findByText("Anna Kowalski");

    await user.selectOptions(await screen.findByLabelText(/Country/), "PL");

    await waitFor(() =>
      expect(screen.getByRole("link", { name: /export csv/i })).toHaveAttribute(
        "href",
        expect.stringContaining("country_code%5B%5D=PL"),
      ),
    );
  });

  // The file is the whole result, so carrying the page boundary into it would
  // silently export one page of it.
  it("leaves the page boundary behind", async () => {
    stubDirectory(page([employee()], { page: 3, total_count: 9565, total_pages: 383 }));

    renderWithProviders(<DirectoryPage />, { route: "/employees?page=3" });
    await screen.findByText("Anna Kowalski");

    const href = screen.getByRole("link", { name: /export csv/i }).getAttribute("href") ?? "";
    expect(href).toContain("/api/v1/employees.csv");
    expect(href).not.toContain("page=");
  });
});
