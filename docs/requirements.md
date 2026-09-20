# Requirements — Salary Management

## Goal

Give ACME's HR Manager one trustworthy place to **maintain** salary data for ~10,000 employees
across multiple countries and to **answer questions** about how the organisation pays people,
replacing a process run on spreadsheets. Spreadsheets fail for three reasons, and those define what
the software must fix:

1. **No history.** Overwriting a salary cell destroys what someone used to earn.
2. **No comparability.** A row in INR and a row in GBP cannot be summed, sorted or compared.
3. **No safe answers.** "What do we spend on payroll in Germany?" becomes a hand-built pivot table
   nobody can reproduce or trust.

**Primary user: the HR Manager**, a single persona who needs to find an individual quickly, correct
or raise their pay, and answer questions from Finance and leadership without building that pivot.

## In scope

| # | Capability | Why |
| --- | --- | --- |
| 1 | **Employee directory** — search by name/email; filter by country, department, level; paginated and sorted server-side | The everyday task. Must stay fast at 10,000 rows. |
| 2 | **Employee detail with full salary history**, effective-dated | Fixes (1). Optional per the team; kept deliberately — see below. |
| 3 | **Record a salary change** — a new effective-dated record, never an in-place edit | Makes history a by-product of normal use rather than a discipline. |
| 4 | **Multi-currency normalisation** — stored local, converted to a base currency for comparison | Fixes (2). The core domain problem. |
| 5 | **Compensation analytics** — payroll cost, distribution and percentiles, compared across country, department and level | Fixes (3). The "how do we pay people?" surface. |
| 6 | **CSV export** | HR is migrating *from* Excel; Finance will still ask for a file. |

## Out of scope — and why

| Excluded | Reasoning |
| --- | --- |
| **Authentication & authorisation** | One persona with full access. A single-role login would cost build time without exercising the domain. First thing to add before real use — salary data is as sensitive as internal data gets. |
| **Outlier / pay-equity flagging** | Needs a defensible peer group first, and the obvious one is wrong: an L5 in India earns less than an L3 in the US. A confident-looking list built on a bad definition is worse than none. The breakdown exposes the quartiles, so a filtered directory answers it with the manager's judgement in the loop. |
| **Payroll runs, payslips, tax, statutory deductions** | An entire regulated domain per country. The brief asks to *manage* salary data, not to disburse it. |
| **Live FX rate API** | Rates are seeded into an effective-dated table. Deterministic, offline, and more correct — a historical salary converts at the rate of its own period, not today's. |
| **Bonus, equity, benefits, allowances** | Total rewards multiplies the domain. Base salary alone demonstrates history, currency and aggregation; the record is shaped so components can be added later without restructuring. |
| **Bulk salary changes** | The append-only model already makes the write path a loop over the existing command. What is missing is preview-before-apply and undo — its own increment. |
| **Bulk CSV import** | Export is in; import is out. A trustworthy migration needs validation, dry-run and partial-failure reporting. The seed script covers getting 10,000 employees in. |
| **Approval workflows** | Implies a second persona and a state machine. Outside the stated problem. |
| **Employee self-service** | Different persona, different access rules, different product. |
| **Org hierarchy / reporting lines** | Interesting for analytics, not needed for the stated questions, and it pulls in recursive queries. |
| **Soft deletes / general audit log** | Salary history is versioned, which covers the question that actually gets asked. An audit log is infrastructure, not product. |

Confirmed with the team on 2026-09-20 (full answers in `docs/clarifying-questions.md`): nothing above
had to be unwound. Two items were left to my judgement rather than required, and both were choices:

- **Salary history was optional.** Kept — here it is not an extra feature but the *absence* of a
  mutable `salary` column, which is what makes corrections non-destructive, `as_of` analytics free,
  and a leaver drop out of payroll cost without a second definition of "active".
- **The analytics set was mine to define.** Narrowed to cost, distribution and comparison; outlier
  detection moved to the table above.

## Key design decisions

Recorded in full in `docs/architecture.md`; here because they shape scope.

- **Money is integer minor units** with an explicit currency, never a float. Floating-point money is
  a correctness bug, not a rounding preference.
- **Compensation is effective-dated and append-only.** "Current salary" is a query, not a column.
- **Conversion uses the rate effective at the compensation's own date**, so historical figures stay
  stable rather than shifting every time the market moves.
- **Aggregation happens in SQL, not Ruby.** No endpoint loads the dataset into memory.

## Success criteria

1. Directory list and analytics respond in well under a second against the full 10,000-employee seed.
2. Any figure shown in a mixed-currency view is explicitly labelled with its base currency and the
   conversion basis.
3. A salary change never destroys the previous value.
4. The test suite is fast, deterministic, and readable as a description of the domain.
