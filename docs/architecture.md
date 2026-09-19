# Architecture

How the system is put together, and why. Decisions are recorded with the alternatives that were
rejected, since the rejected option is usually the more informative half.

---

## 1. System shape

```
┌─────────────────────────────┐         ┌──────────────────────────────────┐
│  web/  React + TypeScript   │         │  api/  Rails 7.1 (API mode)      │
│                             │  JSON   │                                  │
│  · Employee directory       │ ──────► │  Controllers  (thin, HTTP only)  │
│  · Employee detail+history  │ ◄────── │  Queries      (read paths)       │
│  · Compensation analytics   │  HTTP   │  Commands     (write paths)      │
│                             │         │  Models       (domain rules)     │
│  Server-driven pagination   │         │                                  │
└─────────────────────────────┘         └────────────────┬─────────────────┘
                                                         │
                                                ┌────────▼─────────┐
                                                │   PostgreSQL     │
                                                │  aggregation in  │
                                                │  SQL, not Ruby   │
                                                └──────────────────┘
```

Two deployables. The UI holds no domain rules — it renders what the API computes. Every figure a
user sees is produced by one SQL query, so the number on screen and the number in a CSV export
cannot drift apart.

## 2. Domain model

```mermaid
erDiagram
    DEPARTMENT ||--o{ EMPLOYEE : "groups"
    EMPLOYEE   ||--o{ COMPENSATION : "is paid over time"
    CURRENCY   ||--o{ COMPENSATION : "paid in"
    CURRENCY   ||--o{ EXCHANGE_RATE : "quoted for"

    EMPLOYEE {
        bigint  id
        string  employee_number  "unique, external ref"
        string  first_name
        string  last_name
        string  email            "unique"
        string  country_code     "ISO 3166-1 alpha-2"
        bigint  department_id
        string  job_title
        string  job_level        "band, used as the peer group"
        date    hired_on
        date    ended_on         "null while active"
    }

    COMPENSATION {
        bigint  id
        bigint  employee_id
        bigint  amount_minor       "integer minor units, as paid"
        string  currency_code
        bigint  amount_base_minor  "converted, immutable once written"
        numeric exchange_rate_used
        date    effective_from
        date    effective_to       "null = current"
        string  reason             "hire|merit|promotion|market|correction"
        string  note
    }

    EXCHANGE_RATE {
        bigint  id
        string  base_currency_code
        string  quote_currency_code
        numeric rate               "numeric(18,8)"
        date    effective_from
        date    effective_to
    }
```

`Employee` holds identity and placement. `Compensation` holds everything that changes over time.
That split is the whole design: an employee's pay is not an attribute of the employee, it is a
series of dated facts about them.

---

## 3. Key decisions

### ADR-1 — Money is stored as integer minor units

**Context.** Salaries are summed, averaged and converted across currencies.

**Decision.** Store `amount_minor` as a `bigint` (1 234.56 EUR → `123456`) alongside an explicit
`currency_code`. Never a float.

**Consequences.** All arithmetic is exact. Rounding happens once, deliberately, at conversion and
at display. An amount is meaningless without its currency, so the two always travel together.

**Rejected.** `float`/`double` — binary floating point cannot represent 0.1 exactly, and errors
compound across 10,000 rows. `decimal` would be correct but invites accidental float coercion in
Ruby and hides the currency question.

---

### ADR-2 — Compensation is effective-dated; amounts are never mutated

**Context.** The requirement is that a salary change must never destroy the previous value.

**Decision.** Each `Compensation` row carries `effective_from` and `effective_to`. The current
record is the one with `effective_to IS NULL`. Recording a change closes the open record by setting
its `effective_to`, then inserts a new one.

Integrity is enforced in the database, not just in Ruby:

- a `GiST` exclusion constraint prevents two compensation periods for the same employee from
  overlapping;
- a partial unique index on `(employee_id) WHERE effective_to IS NULL` guarantees exactly one
  current record per employee.

**Consequences.** No amount is ever overwritten — only a period is closed — so history is a
by-product of normal use. A correction is itself a dated record with `reason = correction`, which
means mistakes are visible rather than erased.

**On "current".** The word means two different things, and conflating them was a real bug. A raise
agreed in September to start in January is written as an open-ended period the moment it is
recorded, so `effective_to IS NULL` is *not* the same as "what this person is paid today". The
first is a fact about the write path — the row the command closes, and the one the partial unique
index allows exactly one of. The second is a question about a date, and it is answered by
`effective_on(date)` everywhere: the directory, the detail page, the history badge, and analytics.
Reading the open-ended row as today's pay would have shown people a salary they were not yet being
paid, and inflated payroll cost with it.

**On concurrency.** `RecordSalaryChange` originally took `SELECT ... FOR UPDATE` on the outgoing
period. It was removed after measurement: a row lock cannot prevent a concurrent *insert* of a row
that does not exist yet, which is precisely this race, and with two threads racing the loser failed
identically with and without it. The two database constraints above are the actual guarantee, and
the command now translates their violation into a `ConcurrentChange` the API answers as `409`.
Leaving the lock in place would have implied a protection it does not provide.

This is verified in `spec/integration/concurrent_salary_changes_spec.rb`, which runs two real
threads against a real database — the only way to know whether the claim is true.

**Rejected.** *A `salary` column on `employees`* — destroys history on every update; the original
problem. *Pure append-only with no `effective_to`* — philosophically cleaner, but every read needs
`DISTINCT ON` or a window function, which makes the hot path (the 10,000-row directory) markedly
more expensive, and overlapping periods become impossible to constrain in the database.

---

### ADR-3 — Historical rates, and why that makes denormalisation safe

**Context.** Comparing or summing salaries across countries requires a common currency.

**Decision.** Convert each compensation at the exchange rate effective on its **own**
`effective_from` date, not at today's rate. Rates live in an effective-dated table, seeded rather
than fetched from a live API.

**Consequences.** Reported figures are reproducible — last year's payroll cost does not move
because the market moved today. Tests are deterministic and run offline.

This choice then unlocks a performance property. Because a compensation's date never changes, and
the rate for that date never changes, **the converted amount is immutable once written**. So
`amount_base_minor` is computed at write time and stored. The usual objection to denormalisation —
cache invalidation — does not apply, because there is no event that could invalidate it.

The directory can therefore sort and filter on a single indexed integer column, and analytics can
aggregate without joining to rates at all. A correctness decision paid for itself in speed.

The `exchange_rate_used` is stored alongside so any converted figure can be explained and audited.

**Cost, stated honestly.** Changing the organisation's base currency requires a backfill migration.
That is a rare, deliberate, offline operation, and an acceptable price.

**Rejected.** *Live FX API* — non-deterministic tests, network dependency, and historical figures
that drift daily. *Convert on read at today's rate* — same drift problem, plus a rate join on every
query.

---

### ADR-4 — Aggregation happens in SQL

**Context.** Analytics must answer questions over the full population.

**Decision.** Every aggregate — totals, medians, percentiles, distributions — is expressed as SQL.
Medians use Postgres `percentile_cont(...) WITHIN GROUP (ORDER BY ...)`. No endpoint loads the
dataset into Ruby objects.

**Consequences.** Response time is governed by the index, not by object allocation. 10,000
`ActiveRecord` instances cost far more in memory and GC than the query itself costs in Postgres.

**Rejected.** *Ruby-side `map`/`sum`* — readable at 10 rows, indefensible at 10,000, and it makes
the "how do we pay people?" page the slowest part of the product. *Materialised rollups* — the
right answer at a million employees, premature at ten thousand; noted in the improvements list.

---

### ADR-5 — Thin controllers, with queries and commands as objects

**Context.** The two interesting operations are a filtered read and a transactional write.

**Decision.** Controllers parse HTTP and nothing else.

| Layer | Responsibility | Example |
| --- | --- | --- |
| Model | Invariants true of the record in isolation | `Compensation` rejects a non-positive amount |
| Query | Composable read paths | `EmployeeDirectoryQuery` — search, filter, sort, paginate |
| Command | Multi-step writes in a transaction | `RecordSalaryChange` — close period, convert, insert |
| Serializer | Shaping the JSON response | `EmployeeSerializer` |

**Consequences.** Each piece is unit-testable without HTTP. Filtering logic is tested directly
against the database rather than through a controller.

**Rejected.** *Fat models* — `Employee` would accumulate unrelated reporting concerns. *Logic in
controllers* — untestable without the full request cycle, and impossible to reuse for CSV export.

---

### ADR-6 — Money crosses the wire as minor units, formatted in the browser

**Context.** ADR-1 keeps money exact in the database. That guarantee has to survive the JSON
response, and JSON numbers are IEEE 754 doubles — `120000.55` is not representable exactly.

**Decision.** Every amount is serialised as `{ amount_minor, currency_code, minor_unit }`. The
client formats with `Intl.NumberFormat`; it never does arithmetic on the value.

**Consequences.** The UI needs a formatting helper rather than rendering a field directly. In
exchange, the exponent travels with the amount, so the client cannot assume two decimals and
display ¥15,000,000 as ¥150,000.00.

**Rejected.** *A pre-formatted string* (`"$120,000.55"`) — unsortable, unparseable, and bakes the
server's locale into the response. *A float* — precision loss on exactly the field that must not
lose precision.

---

### ADR-7 — A trigram index for directory search

**Context.** HR searches by fragments: part of a surname, the tail of an employee number. That is
`ILIKE '%term%'`, and a leading wildcard makes a btree index unusable, leaving a sequential scan
over 10,000 rows for every keystroke.

**Decision.** One GIN trigram index over the concatenation of the four searchable columns
(`first_name`, `last_name`, `email`, `employee_number`), with `Employee::SEARCHABLE_TEXT` holding
the identical expression the query uses.

**Consequences.** Measured on the full seed, search drops from a sequential scan to a bitmap index
scan — 0.27 ms for 88 matches out of 10,000. Searching across first and last name together ("Anna
Kowalski") works for free, because the index is on the joined string.

The risk is drift: change the expression in the model without a matching migration and search
silently becomes a sequential scan again. A spec runs `EXPLAIN` with `enable_seqscan = off` and
asserts the index name appears in the plan, so the drift fails the build instead of the demo.

**Rejected.** *Four separate `ILIKE` clauses* — four indexes, and no match across a full name.
*PostgreSQL full-text search* — stems and tokenises, so "kowal" would not match "Kowalski"; it
answers a different question than the one HR is asking.

---

## 4. Performance approach

The directory is the hot path: 10,000 employees, filtered, sorted, paginated.

- **Server-side pagination always.** The API never returns an unbounded collection.
- **Sorting by pay uses the stored `amount_base_minor`** — one integer column, no join to rates
  (ADR-3). Measured, this sort is a top-N heapsort over the joined population either way: 10.2 ms
  when compensation was selected by partial index, 9.9 ms when selected by effective date. The
  index was not what made it fast, and `pg_stat_user_indexes` shows the partial index added for
  this purpose was never once scanned. Recorded here because the original claim was wrong.
- **Covering indexes on the real filter combinations** — country, department, job level.
- **No N+1.** The directory joins current compensation once; violations are caught by a test, not
  by inspection.

Measurements with `EXPLAIN (ANALYZE, BUFFERS)` against the full seed are recorded in
`docs/performance.md` as the queries are built, so the claims here are evidenced rather than
asserted.

## 5. Testing approach

- **RSpec + FactoryBot.** Model specs for invariants, query specs against real SQL, request specs
  for API contracts.
- **Deterministic.** Dates are frozen with `travel_to`; seeded data uses a fixed random seed. No
  test depends on today's date, on ordering luck, or on the network.
- **Fast.** Transactional cleanup, no `sleep`, no HTTP in unit tests.
- **Readable as documentation.** Test names state domain rules — "closes the previous period when a
  raise is recorded" — not mechanics.

The suite is the specification of the domain. A reader should be able to learn the rules of
compensation from the spec files alone.
