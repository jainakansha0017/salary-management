# Working with AI on this exercise

A record of how AI was used to build this, what it got right, and — more usefully — the places it
was confidently wrong and how that was caught. The failures are the interesting part: they are what
tells you where the review has to be real.

---

## 1. The setup

**Tool:** Claude Code (Anthropic's CLI agent), driven from a terminal in the repository root. It can
read and write files, run `rspec`, `rubocop`, `vitest` and `psql`, and drive a browser against the
running app.

**Working agreement, agreed before any code was written:**

> Build one commit at a time. Stop after each one. I review it before you start the next.

That single constraint shaped everything else. A commit is small enough to actually read, it carries
a message that has to justify itself, and `git log` becomes the record of the session. When something
was wrong, the blast radius was one commit rather than an afternoon's work.

**What was not delegated:** the domain decisions. Effective-dated, append-only compensation; money as
integer minor units carrying its own exponent; aggregation in SQL rather than Ruby; the choice to send
clarifying questions rather than guess at scope. Those were decided first, written into
[`docs/architecture.md`](architecture.md) as ADRs with their rejected alternatives, and the AI built
against them. Asking an agent to choose your domain model gets you a plausible one, and plausible is
not the bar for a salary system.

---

## 2. How the work was framed

The prompts that produced good code had a shape in common. They described a behaviour and a
constraint, and left the implementation open.

**Worked:**

> Compensation is append-only and effective-dated. Half-open ranges. Two changes for the same
> employee must never produce two open-ended periods, and I want that guaranteed by the schema, not
> by a callback. Write the migration and the model, with specs that fail if the guarantee is removed.

The last clause is the one that matters. "Specs that fail if the guarantee is removed" is a testable
instruction; "write tests" is not, and produces tests that assert the implementation back at you.

> Measure it. Don't tell me it's fast, show me `EXPLAIN (ANALYZE, BUFFERS)` against the full
> 10,000-employee seed.

**Did not work:**

> Build the analytics dashboard.

Too large. What came back was structurally fine and wrong in a dozen small ways at once — which is
exactly the situation where you stop reviewing and start skimming. Re-framed as "the summary
endpoint's numbers, as a page; no charting library; tables that a screen reader can read" it was
reviewable.

**The most valuable single instruction** turned out to be a standing one about comments:

> Comments explain why, not what. If a comment restates the line below it, delete it.

This does more than tidy the source. A comment that has to justify a decision is a comment that
exposes a decision that cannot be justified — several of the corrections in the next section surfaced
because the AI could not write a defensible reason for something it had just written.

---

## 3. Where it was wrong

### 3.1 It told me the API allowed something it forbids

Asked whether HR could backdate a salary change, the answer was a confident "yes, and future-dating
too". Reading `RecordSalaryChange` showed the opposite: it raises `BackdatedChange` when
`effective_from` is on or before the current period's start, and the API answers 422. The UI was
being designed around a capability that did not exist.

This is the characteristic failure mode — not broken code, but a confident statement about code that
nobody checked against the code. It was caught by reading the command, not by asking again. Asking
again usually gets you the same answer with more conviction.

### 3.2 Two meanings of "current", and a bug that shipped between them

`c5ce6ab`. A raise agreed in September to start in January is stored as an open-ended period the
moment it is recorded. The directory read "open-ended" as "current pay", so it displayed a salary
people were not yet being paid, sorted by it, and badged it *Current* in their history. The analytics
endpoints had it right, which is what made the inconsistency visible at all.

The AI wrote both halves and did not notice they disagreed. The fix was to make the confusion
impossible rather than to patch the read: `Compensation.current` is the open-ended period (what the
write path closes), `effective_on(date)` is what someone is actually paid on a date, and
`current_compensation` was renamed to `effective_compensation` so the rename forced every call site
to be looked at.

### 3.3 A lock that guaranteed nothing

`be35fa2`. Concurrent salary changes for one employee returned 500 with a Postgres constraint name in
the response body. The first fix offered was `SELECT ... FOR UPDATE`, which is the textbook answer and
is useless here: a row lock cannot prevent a concurrent insert of a row that does not exist yet, and a
phantom is exactly what this race is.

Writing a spec that runs two real threads against a real database showed the losing thread failing
identically with the lock and without it. What actually holds the invariant is the schema — the GiST
exclusion constraint on overlapping periods and the partial unique index allowing one open-ended
period per employee. The lock was removed rather than left in place implying a guarantee it does not
give, and the ADR records the removal so that the next person does not helpfully add it back.

### 3.4 An index justified by assumption

`aaa8e69`, then `c70e731`. `index_current_compensations_on_base_amount` was added on the reasoning
that sorting the directory by pay would walk it in order. Measured against the full seed it never did:
top-N heapsort over the joined population either way, 10.2 ms with it and 9.9 ms without.

The interesting part is the second-order correction. `pg_stat_user_indexes` reported zero scans, and
that was nearly taken as proof — until benchmarking a job-level filter made *that* index's counter go
from zero to non-zero. Zero scans means "never exercised", not "useless". The index was dropped on
plan evidence instead. The same measuring session found the first benchmark had been running inside
the ActiveRecord query cache, so the "warm" figures were a hash lookup rather than Postgres: the
payroll summary is 16.2 ms, not the 1.2 ms previously recorded and quoted in the architecture doc.

Both wrong numbers were AI-generated, both were plausible, and both survived until something was
actually measured.

### 3.5 Floating-point money, caught in review

The salary form's first draft converted the typed amount with `Number(input) * 100`. In IEEE-754,
`95000.55 * 100` is `9500054.999999999`. Rounding that back is a coin flip on the last penny of
somebody's salary. `toMinorUnits` now shifts the decimal point by moving characters in the string, and
returns `null` rather than a guess for anything that isn't a plain positive amount — including more
decimal places than the currency has, because a JPY salary of `15000.75` is a typo, not a value to
truncate silently.

### 3.6 A doc that cited a file that did not exist

`7d91cd4`. `architecture.md` had been claiming that `EXPLAIN (ANALYZE, BUFFERS)` measurements were
recorded in `docs/performance.md`. There was no such file. Generated prose will cheerfully cross-
reference things it expects to exist. Every internal link in these documents was opened once.

### 3.7 Tests that were ambiguous, which turned out to be a real defect

Two analytics tests failed on ambiguity rather than behaviour. `findByText("Median")` matched three
places — the headline block, the percentile strip, and a table column. `findByText("Engineering")`
matched both a table cell and an `<option>` in the department filter.

The lazy fix is `getAllBy...[0]`. The honest reading is that if a test cannot say which "Median" it
means, neither can a screen reader. The card blocks became `<section aria-label="Payroll totals">`
and `aria-label="Salary percentiles"`, the assertions scoped to those regions, and the other test
moved to `findByRole("cell", ...)`. Three further tests that had been passing only because the table
happened to render before the filter options were fixed the same way.

---

## 4. What the AI was genuinely good at

- **Volume with structure.** The 10,000-employee seed — ten countries, weighted level distributions,
  multi-year salary histories, a fixed random seed so the numbers in the docs can be re-checked
  rather than trusted — is tedious to write and was correct almost immediately.
- **SQL that is annoying to get right.** `percentile_cont(...) WITHIN GROUP` and `width_bucket(...)`
  for the distribution bands, in one query per figure, so the number on screen and the number in the
  CSV export cannot drift apart.
- **The second half of a pattern.** Once the first query object and its spec existed, the rest of
  them matched without being told to.
- **Being argued with.** Pushing back on the lock, on the index, and on `getAllBy...[0]` produced
  better reasoning each time rather than agreement. Politely accepting the first answer is where the
  quality goes.

## 5. What I would do differently

- **Ask it to measure earlier.** Three of the seven corrections above are numbers that were asserted
  instead of measured. "Show me the plan" should have been standing policy from the first query, not
  something introduced once the seed existed.
- **Read the code before asking about the code.** The backdating mistake cost more than reading
  `RecordSalaryChange` would have.
- **Keep the commits small even when it is going well.** The two that needed the most rework were the
  two largest.

## 6. Honest summary

Roughly 30 commits, 191 Rails examples and 77 frontend tests. Most of the typing is AI-generated. The
domain model, the invariants, the decision to measure rather than assert, and every correction in
section 3 came from review — and the review only worked because the commits were small enough to
read properly and the tests were written to fail when the guarantee they describe is removed.

The tool is a fast, tireless, confident pair who has not read your schema. That is genuinely worth
having, at the cost of never taking its word for anything that a query, a spec or a browser can be
made to answer instead.
