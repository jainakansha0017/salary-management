import { afterEach, describe, expect, it, vi } from "vitest";
import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { Route, Routes } from "react-router-dom";
import { EmployeePage } from "./EmployeePage";
import { renderWithProviders, stubFetch } from "../test/harness";
import type { RecordedRequest } from "../test/harness";
import type { Compensation, EmployeeDetail } from "../api/types";

afterEach(() => vi.unstubAllGlobals());

function compensation(overrides: Partial<Compensation> = {}): Compensation {
  return {
    id: 1,
    amount: { amount_minor: 17_260_000, currency_code: "PLN", minor_unit: 2 },
    base_amount: { amount_minor: 4_401_300, currency_code: "USD", minor_unit: 2 },
    exchange_rate_used: "0.255",
    effective_from: "2025-08-16",
    effective_to: null,
    current: true,
    reason: "merit_increase",
    note: null,
    ...overrides,
  };
}

function person(overrides: Partial<EmployeeDetail> = {}): EmployeeDetail {
  const history = overrides.salary_history ?? [compensation()];
  const current = history.find((period) => period.current);

  return {
    id: 42,
    employee_number: "ACME-00042",
    full_name: "Anna Kowalski",
    email: "anna.kowalski@acme.example",
    country_code: "PL",
    department: "Engineering",
    department_id: 11,
    job_title: "Staff Engineer",
    job_level: "L5",
    hired_on: "2021-03-01",
    ended_on: null,
    active: true,
    current_salary: current
      ? {
          amount: current.amount,
          base_amount: current.base_amount,
          effective_from: current.effective_from,
        }
      : null,
    ...overrides,
    salary_history: history,
  };
}

/**
 * Renders at a real route so `useParams` supplies the id the way the router
 * does, rather than the component being handed one a test made up.
 */
function renderEmployee() {
  return renderWithProviders(
    <Routes>
      <Route path="/employees/:id" element={<EmployeePage />} />
    </Routes>,
    { route: "/employees/42" },
  );
}

function posted(requests: RecordedRequest[]): RecordedRequest | undefined {
  return requests.find((request) => request.method === "POST");
}

describe("the employee detail page", () => {
  it("shows who the person is and what they are paid", async () => {
    stubFetch({ "/api/v1/employees/42": { body: { data: person() } } });
    renderEmployee();

    expect(await screen.findByRole("heading", { name: "Anna Kowalski" })).toBeInTheDocument();
    expect(screen.getByText("ACME-00042 · Staff Engineer")).toBeInTheDocument();

    // Scoped to the headline rather than the page: the same figure appears in
    // the history table below, so a bare text query would pass even if the
    // headline were missing.
    const headline = screen.getByText("Current salary").nextElementSibling;
    // A plain space, though the DOM holds U+00A0: `toHaveTextContent`
    // normalises whitespace before comparing, and the separator being
    // non-breaking is asserted in `format.test.ts` where it is the point.
    expect(headline).toHaveTextContent("PLN 172,600.00");
    // The base-currency figure earns its place only by differing from the one
    // above it, which for a Polish salary it does.
    expect(headline).toHaveTextContent("$44,013.00");
  });

  it("lists the history newest first, as the server ordered it", async () => {
    stubFetch({
      "/api/v1/employees/42": {
        body: {
          data: person({
            salary_history: [
              compensation({ id: 2, reason: "promotion" }),
              compensation({
                id: 1,
                amount: { amount_minor: 14_000_000, currency_code: "PLN", minor_unit: 2 },
                effective_from: "2021-03-01",
                effective_to: "2025-08-16",
                current: false,
                reason: "hire",
              }),
            ],
          }),
        },
      },
    });
    renderEmployee();

    const rows = await screen.findAllByRole("row");
    expect(within(rows[1]!).getByText("Promotion")).toBeInTheDocument();
    expect(within(rows[2]!).getByText("Hire")).toBeInTheDocument();
  });

  // The distinction the server draws with `current`: a raise agreed today to
  // start in January is open-ended but is not what the person is being paid.
  it("calls a future-dated period scheduled, not current", async () => {
    stubFetch({
      "/api/v1/employees/42": {
        body: {
          data: person({
            salary_history: [
              compensation({ id: 2, effective_from: "2027-01-01", current: false }),
              compensation({ id: 1, effective_to: "2027-01-01" }),
            ],
          }),
        },
      },
    });
    renderEmployee();

    const rows = await screen.findAllByRole("row");
    expect(within(rows[1]!).getByText("Scheduled")).toBeInTheDocument();
    expect(within(rows[2]!).getByText("Current")).toBeInTheDocument();
  });
});

describe("recording a salary change", () => {
  it("sends minor units of the salary's own currency", async () => {
    const { requests } = stubFetch({
      "/api/v1/employees/42/salary_changes": {
        status: 201,
        body: { data: compensation({ id: 3 }) },
      },
      "/api/v1/employees/42": { body: { data: person() } },
    });
    renderEmployee();

    await userEvent.type(await screen.findByLabelText("New salary (PLN)"), "180000.50");
    await userEvent.selectOptions(screen.getByLabelText("Reason"), "promotion");
    await userEvent.clear(screen.getByLabelText("Effective from"));
    await userEvent.type(screen.getByLabelText("Effective from"), "2026-10-01");
    await userEvent.click(screen.getByRole("button", { name: "Record change" }));

    await waitFor(() => expect(posted(requests)).toBeDefined());
    expect(posted(requests)?.body).toEqual({
      salary_change: {
        amount_minor: 18_000_050,
        currency_code: "PLN",
        effective_from: "2026-10-01",
        reason: "promotion",
      },
    });
  });

  it("reloads the employee so the page shows the server's version", async () => {
    const { calls } = stubFetch({
      "/api/v1/employees/42/salary_changes": {
        status: 201,
        body: { data: compensation({ id: 3 }) },
      },
      "/api/v1/employees/42": { body: { data: person() } },
    });
    renderEmployee();

    await userEvent.type(await screen.findByLabelText("New salary (PLN)"), "180000");
    await userEvent.click(screen.getByRole("button", { name: "Record change" }));

    await screen.findByText("Change recorded.");
    const reads = calls.filter((url) => url.endsWith("/api/v1/employees/42"));
    expect(reads.length).toBeGreaterThan(1);
  });

  // The server would reject this too, but its message is in minor units — a
  // vocabulary the person typing a salary has no reason to know.
  it("refuses more precision than the currency has, without asking the server", async () => {
    const { requests } = stubFetch({
      "/api/v1/employees/42": {
        body: {
          data: person({
            salary_history: [
              compensation({
                amount: { amount_minor: 15_000_000, currency_code: "JPY", minor_unit: 0 },
                base_amount: { amount_minor: 10_000_000, currency_code: "USD", minor_unit: 2 },
              }),
            ],
          }),
        },
      },
    });
    renderEmployee();

    await userEvent.type(await screen.findByLabelText("New salary (JPY)"), "16000000.75");
    await userEvent.click(screen.getByRole("button", { name: "Record change" }));

    expect(await screen.findByText("Enter a positive whole amount.")).toBeInTheDocument();
    expect(posted(requests)).toBeUndefined();
  });

  // The backdating rule lives in the command, so the only way the form can
  // report it is by putting what the server said under the field it names.
  it("puts a rejection under the field the server blamed", async () => {
    stubFetch({
      "/api/v1/employees/42/salary_changes": {
        status: 422,
        body: {
          error: {
            code: "validation_failed",
            message: "The salary change was not recorded",
            details: {
              effective_from: ["must take effect after the current salary began on 2025-08-16"],
            },
          },
        },
      },
      "/api/v1/employees/42": { body: { data: person() } },
    });
    renderEmployee();

    await userEvent.type(await screen.findByLabelText("New salary (PLN)"), "180000");
    await userEvent.click(screen.getByRole("button", { name: "Record change" }));

    const problem = await screen.findByText(/must take effect after the current salary began/);
    expect(problem).toBeInTheDocument();
    // Beside the date, not in a list at the top leaving the reader to guess.
    expect(screen.getByLabelText("Effective from").parentElement).toContainElement(problem);
  });

  it("has nothing to change when there is no salary on record", async () => {
    stubFetch({
      "/api/v1/employees/42": {
        body: { body: null, data: person({ salary_history: [], current_salary: null }) },
      },
    });
    renderEmployee();

    expect(await screen.findByText(/no salary on record/)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Record change" })).not.toBeInTheDocument();
  });
});
