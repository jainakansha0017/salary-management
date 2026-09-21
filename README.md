# Salary Management

Web-based salary management for ACME's HR team — replacing the spreadsheets currently used to
track compensation for ~10,000 employees across multiple countries.

Pay is **effective-dated and append-only**: a salary change opens a new period rather than editing
the old one, so "what did this person earn in March" and "what did payroll cost last quarter" are the
same query with a different date. Nothing is overwritten, and there is no month-end snapshot job.

## Documentation

| Document | Purpose |
| --- | --- |
| [Requirements](docs/requirements.md) | Goal, scope, and what is deliberately excluded |
| [Clarifying questions](docs/clarifying-questions.md) | What was asked of the team, and the scope choices left to me |
| [Architecture](docs/architecture.md) | How it is put together, as ADRs with their rejected alternatives |
| [Performance](docs/performance.md) | `EXPLAIN (ANALYZE, BUFFERS)` against the full seed, and what changes at 10× and 100× |
| [AI log](docs/ai-log.md) | How AI was used, and where it was wrong |

## Stack

- **Backend** — Ruby 3.1, Rails 7.1 (API mode), PostgreSQL, RSpec
- **Frontend** — React 18 + TypeScript, Vite, Vitest
- **Layout** — `api/` (Rails), `web/` (React SPA), `docs/` (artifacts)

## Getting started

Requires Ruby 3.1, Node 18.12+, and a running PostgreSQL you can create databases on.

### 1. API

```bash
cd api
bin/setup                 # bundle, create the databases, load structure.sql, seed 10,000 employees
bin/rails server -p 3001
```

`bin/setup` runs `db:prepare`, which seeds a database it had to create — so on a clean machine the
first command is the only one you need. To rebuild the organisation afterwards:

```bash
FORCE=true bin/rails db:seed                      # replace it
EMPLOYEE_COUNT=200 FORCE=true bin/rails db:seed   # a smaller one, for a quick loop
```

The seed refuses to run against a database that already holds employees unless you pass `FORCE`,
because pointing it at real salary data would be unrecoverable. It uses a fixed random generator, so
it produces the same organisation every time — the figures quoted in the docs can be re-checked
rather than taken on trust.

Port 3001 rather than 3000 only because 3000 is the port every Rails app wants; use 3000 if it is free
and drop `API_PROXY_TARGET` below.

### 2. Web

```bash
cd web
npm install
API_PROXY_TARGET=http://localhost:3001 npm run dev
```

Then open <http://localhost:5173>.

Vite proxies `/api` to Rails, so the browser makes no cross-origin request and the dev build calls the
same relative paths the production build does — one code path rather than a branch on the environment.

### 3. Tests

```bash
cd api && bundle exec rspec && bundle exec rubocop    # 191 examples
cd web && npm test && npm run typecheck               # 77 tests
```

## The API

| Endpoint | Answers |
| --- | --- |
| `GET /api/v1/employees` | The directory — search, filter, sort, page. `.csv` exports the same filters without the page boundary |
| `GET /api/v1/employees/:id` | One person, with their full salary history |
| `POST /api/v1/employees/:id/salary_changes` | Record a change. Opens a new period; never edits one |
| `GET /api/v1/filters` | The filter options the directory offers |
| `GET /api/v1/analytics/summary` | Headcount, total, average, percentiles, distribution bands |
| `GET /api/v1/analytics/breakdown` | The same figures grouped by country, department or level |

Both analytics endpoints take `as_of=YYYY-MM-DD`; omitted means today. The directory always prices
people as of today — a page that filtered by one date and priced by another would be inconsistent with
itself — and offers `status` instead, which the analytics endpoints deliberately do not: a payroll
total is a question about who is being paid, and `as_of` already answers it.

Every amount is an integer in **minor units** with its own `minor_unit` exponent and currency code
attached, so nothing in the system has to guess that a number is dollars rather than yen, and no
salary ever passes through a float.
