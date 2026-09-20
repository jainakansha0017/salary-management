# Requirements — Salary Management

## Goal

Give ACME's HR Manager a single, trustworthy place to **maintain** salary data for ~10,000
employees across multiple countries, and to **answer questions** about how the organisation pays
people — replacing a process currently run on spreadsheets.

Spreadsheets fail here for three specific reasons, and those define what the software must fix:

1. **No history.** Overwriting a salary cell destroys the record of what someone used to earn.
2. **No comparability.** A row in INR and a row in GBP cannot be summed, sorted, or compared.
3. **No safe answers.** "What do we spend on payroll in Germany?" becomes a hand-built pivot table
   that nobody can reproduce or trust.

## Primary user

**HR Manager.** Single persona. Needs to look up an individual quickly, correct or raise their pay,
and answer compensation questions from Finance and leadership without building a pivot table.

## In scope

| # | Capability | Why it matters |
| --- | --- | --- |
| 1 | **Employee directory** — search by name/email, filter by country, department and job level, server-side paginated and sorted | The everyday task. Must stay fast at 10,000 rows. |
| 2 | **Employee detail with full salary history** — every compensation record, effective-dated | Directly fixes failure (1). Answers "what were they on last year?" *Confirmed optional by the team; kept deliberately — see below.* |
| 3 | **Record a salary change** — new effective-dated record, never an in-place edit | Makes history a by-product of normal use rather than a discipline. |
| 4 | **Multi-currency normalisation** — salaries stored in local currency, converted to a base currency for any comparison | Directly fixes failure (2). The core domain problem. |
| 5 | **Compensation analytics** — headcount and total payroll cost by country/department, median and percentile pay, salary distribution | Directly fixes failure (3). This is the "how do we pay people?" surface. |
| 6 | **CSV export** | HR is migrating *from* Excel; Finance will still ask for a file. |

## Out of scope — and why

| Excluded | Reasoning |
| --- | --- |
| **Authentication & authorisation** | The brief defines one persona with full access. Adding login would consume time without exercising the domain. Called out as the first thing to add before real use, since salary data is highly sensitive. |
| **Payroll runs, payslips, tax and statutory deductions** | An entire regulated domain per country. The brief asks to *manage salary data*, not to disburse it. |
| **Live FX rate API** | Rates are held in an effective-dated table and seeded. Keeps tests deterministic and offline, and is more correct anyway — a historical salary should convert at the rate of its own period, not today's. Swapping in a rate-fetching job later is a contained change. |
| **Bonus, equity, benefits, allowances** | Modelling total rewards multiplies the domain. Base salary alone is enough to demonstrate history, currency and aggregation. The compensation record is shaped so components can be added without restructuring. |
| **Approval workflows** | Implies a second persona (approver) and a state machine. Out of the stated problem. |
| **Employee self-service** | Different persona, different access rules, different product. |
| **Org hierarchy / reporting lines** | Interesting for analytics ("cost of a manager's org") but not required to answer the stated questions, and it pulls in recursive queries. |
| **Bulk CSV import** | Export is in; import is out. A real migration needs validation, dry-run and partial-failure reporting to be trustworthy — enough substance to be its own increment. The seed script covers getting 10,000 employees in. |
| **Soft deletes / full audit trail** | Salary history is versioned, which covers the question that actually gets asked. A general audit log is infrastructure, not product. |
| **Outlier / pay-equity flagging** | "Who is underpaid?" needs a defensible peer group before it is a feature rather than a number — and an L5 in India earns less than an L3 in the US, so the obvious grouping is the wrong one. Shipping a confident-looking list built on a bad definition is worse than not shipping it. The breakdown already exposes the quartiles, so filtering the directory to a group answers it with the manager's judgement in the loop. |
| **Bulk salary changes** | Confirmed not required. The append-only model makes the write path a loop over the existing command; what is genuinely missing is preview-before-apply and undo, which is its own increment. |

## Scope confirmed with the team (reply of 2026-09-20)

This document was written before building. The team's reply confirmed every assumption in
`docs/clarifying-questions.md` — nothing above had to be unwound. Two answers widened my latitude,
and the choice I made with each is the point:

- **Salary history is optional; a current salary would have sufficed.** Kept anyway, because here it
  is not an extra feature but the absence of a mutable `salary` column. Append-only effective-dated
  records are what make corrections non-destructive, make `as_of` on analytics free, and make a
  leaver drop out of payroll cost without a second definition of "active". A single mutable column
  would have been less code in the model and more code everywhere else.
- **The analytics set is mine to define.** Narrowed to cost, distribution and comparison across
  country/department/level. Outlier detection was in my original assumption and has been dropped to
  the table above, with reasoning.

Also confirmed as out of scope by the team: authentication, bulk changes, and joiner/leaver
workflow. 10,000 employees is the target scale, so no rollup infrastructure; a deterministic FX
approach is acceptable, so no live rate API.

## Key design decisions

These are recorded in full in `docs/architecture.md`; summarised here because they shape scope.

- **Money is stored as integer minor units** (e.g. cents) with an explicit currency, never a float.
  Floating-point money is a correctness bug, not a rounding preference.
- **Compensation is effective-dated and append-only.** "Current salary" is a query
  (`the record whose effective range covers today`), not a column. History is free.
- **Conversion uses the rate effective at the compensation's own date**, so historical figures stay
  stable rather than shifting every time rates move.
- **Aggregation happens in SQL, not Ruby.** 10,000 employees is small for Postgres and large for
  `map`/`sum` over ActiveRecord objects. Analytics endpoints must not load the dataset into memory.

## Success criteria

1. Directory list and analytics respond in well under a second against the full 10,000-employee seed.
2. Any figure shown in a mixed-currency view is explicitly labelled with its base currency and the
   conversion basis.
3. A salary change never destroys the previous value.
4. The test suite is fast, deterministic, and readable as a description of the domain.
