# Clarifying Questions

Sent to the Incubyte team before building. Each question carries the assumption I proceeded on, so
that work continued without blocking on a reply. Answers are recorded inline as they arrive.

**Reply received 2026-09-20.** Every assumption was confirmed or left to my judgement; nothing had
to be unwound. The team's closing note — "capture what you deliberately choose to leave out and your
reasoning" — is answered by the *Out of scope* table in `requirements.md`, which is where those
decisions already live.

Two answers gave me more latitude than I had assumed, and both are recorded as deliberate choices
rather than requirements: salary **history** is optional (I kept it — see Q2), and the **analytics
set** is mine to define (I narrowed it — see Q1).

---

## Product & scope

### 1. Which questions must the HR Manager be able to answer?

The brief says the HR Manager should "be able to answer questions about how the org pays people."
That phrase is doing a lot of work, and it defines the entire analytics surface. If you have a top
five in mind, I would rather build the right five than guess at fifteen.

> **Working assumption:** the recurring ones are — total payroll cost (overall, and sliced by
> country and department), median and percentile pay for a given role or level, how pay is
> distributed within a band, headcount per slice, and identifying outliers such as people paid well
> below the median for their peer group.

**Answer:** No predefined set — define a focused one from the persona and problem statement. "Salary
cost, distribution, and comparisons across country/department/role are reasonable examples."

**What I did with that.** I built exactly those three and dropped the fourth from my assumption:

- **Cost and distribution** — `GET /analytics/summary`: headcount, total, mean, min/max, five
  percentiles and a histogram, for any filtered population on any date.
- **Comparison** — `GET /analytics/breakdown?dimension=`: the same figures repeated per country,
  department or job level, which is the view that makes a pay gap visible.
- **Outlier detection** (people paid below their peer group) was in my assumption and is *not*
  built. It is the natural next increment, and the breakdown query already computes the quartiles it
  would compare against — but "who is underpaid?" needs a defensible definition of a peer group
  before it is a feature rather than a number, and defining that badly is worse than not shipping it.
  Filtering the directory to a group and reading its p25 from the summary answers the same question
  today with the manager's judgement in the loop.

---

### 2. Is salary *history* in scope, or only each employee's current salary?

This is the single biggest driver of the data model. History means compensation is an
effective-dated, append-only series rather than a column on the employee record.

> **Working assumption:** in scope. An HR manager asking "how do we pay people?" almost always also
> asks "and how has that changed?" Append-only records also mean a correction can never silently
> destroy the previous value. I have modelled it this way.

**Answer:** Current salary is sufficient. History is optional — include it if I believe it adds
value.

**What I did with that.** Kept it, and it is the decision I would defend hardest. History here is
not a feature bolted onto a salary column; it is the *absence* of one. Compensation is an
effective-dated, append-only series, and "current salary" is the record whose range covers today.

That single choice is what makes three other things true rather than special-cased:

- A correction cannot silently destroy the previous value, because writes only ever append.
- Historical figures are answerable — `as_of` on every analytics endpoint costs nothing extra,
  because the query was already date-scoped.
- A leaver is excluded from payroll cost for free: their final period closes on their leaving date,
  so no separate notion of "who counted as employed then" is needed (see Q5).

Storing a single mutable `salary` column would have been *less* code in the model and more
everywhere else. I would rather be judged on this than on having taken the shortcut that was offered.

---

### 3. How should multi-currency comparison work?

Employees sit across multiple countries, so aggregate figures need a common unit. Two sub-questions:

- Does ACME have a single reporting/base currency, or should the HR Manager choose one per view?
- When converting a *historical* salary, should it use the rate in effect at the time of that
  salary, or today's rate?

> **Working assumption:** a configurable base currency defaulting to USD, and conversion at the rate
> effective on the compensation record's own date. Converting history at today's rate would make
> last year's reported payroll cost change every time the market moves, which makes the numbers
> unreproducible. I am storing effective-dated rates rather than calling a live FX API, which also
> keeps the test suite deterministic and offline.

**Answer:** Intentionally open. Local currencies, normalisation to a common reporting currency, or
both. "If you choose conversion, a fixed/deterministic FX approach is acceptable."

**What I did with that.** Both, and the deterministic FX is effective-dated rather than fixed — a
seeded rate table keyed by date, not a constant. The extra cost over a flat rate was one table and a
lookup; the payoff is that last year's reported payroll cost does not move when the market does.

Every amount is served in its local currency *and* the base currency, each labelled with its own
exponent, so no client has to guess whether a figure has been converted.

---

### 4. Should the HR Manager be able to apply bulk changes?

For example, "give everyone in Engineering in India a 6% increase." This is genuinely common in
annual review cycles, but it needs preview-before-apply and a way to undo, which is a meaningful
chunk of work.

> **Working assumption:** out of scope for this submission. Single-employee salary changes only. I
> have noted it as a natural next increment, since the append-only model already supports it
> cleanly.

**Answer:** Not required. Single-employee salary updates are sufficient.

**What I did with that.** Left out, as assumed. Recorded in `requirements.md` as a next increment:
the append-only model already makes it a loop over the same command object, so what is missing is
the preview-and-undo affordance, not the write path.

---

### 5. Do we track joiners and leavers?

It affects what "total payroll cost" means — whether it counts only currently active employees, and
whether someone who left mid-year still contributes to a historical figure.

> **Working assumption:** employees have a hire date and an optional end date. Analytics count
> active employees by default, and the UI states this explicitly so the number is never ambiguous.

**Answer:** Not required — the focus is salary management for the seeded employees. "You may define
how active/inactive employees are handled if relevant to your solution."

**What I did with that.** Defined it, because payroll cost is meaningless without it, but defined it
*once* rather than twice. Employees carry a hire date and an optional end date, and analytics derive
their population from compensation rather than from that status: whoever had a salary period in
effect on `as_of`.

Because a leaver's final period is closed on their leaving date, that one rule excludes departed
staff without a second definition of "active", and it keeps historical dates answerable. The
directory filters on the employment dates directly, since "show me the leavers" is a different
question from "what did we pay in June".

---

## Non-functional

### 6. Is authentication expected?

The brief names one persona with full access. Salary data is about as sensitive as internal data
gets, so I do not want to appear casual about it.

> **Working assumption:** out of scope, and documented as the first thing to add before real use.
> My reasoning is that a single-role login would consume build time without exercising any of the
> interesting parts of this domain. Happy to add it if you would rather see it.

**Answer:** Not explicitly required. A single HR Manager role is sufficient.

**What I did with that.** Left out, as assumed, and still named in `requirements.md` as the first
thing to add before real use — a public URL serving 10,000 real-shaped salaries is not a thing I
would want to be casual about, even with permission.

---

### 7. Is 10,000 employees the target, or a starting point?

It changes what "good performance" means. At 10,000 rows, correct indexing and aggregation in SQL
are sufficient. At 1,000,000, I would be looking at materialised rollups for the analytics views.

> **Working assumption:** 10,000 is the real target. I am designing so the system does not fall over
> beyond that — all aggregation happens in SQL rather than in Ruby, and nothing loads the full
> dataset into memory — but I am not pre-building rollup infrastructure for a scale you have not
> asked for.

**Answer:** Treat 10,000 as the seed/target scale; the solution should demonstrably work with the
provided dataset.

**What I did with that.** Held the line on no rollup infrastructure, and measured instead of
asserting. Against the full seed: payroll summary 33 ms cold and under 2 ms warm; each breakdown
1.3–1.5 ms; the directory's first page 125 ms cold. All aggregation is `percentile_cont` and
`width_bucket` in Postgres — no endpoint loads the dataset into Ruby.

Measurement also removed something: an index added speculatively for the salary sort turned out to
have zero scans over the database's entire lifetime, so it was dropped rather than left in the
schema claiming a performance property it did not have.

---

## Logistics

### 8. What is the deadline, and roughly what time investment do you expect?

I would rather calibrate depth to your expectations than over- or under-build.

> **Working assumption:** proceeding at a scope I can deliver to a high standard.

**Answer:** Follow the deadline communicated with the assessment.

---

### 9. For "fully functional deployed software" — is a free-tier public URL acceptable?

And does it need to remain live through the interview rounds?

> **Working assumption:** yes, a public URL on a free tier, kept live through the process.

**Answer:** No preferred platform. A publicly accessible free-tier deployment is acceptable, as long
as the application is functional and reviewable.

---

### 10. In what form would you like the AI artifacts?

You have asked for "prompts or instructions used with AI tools." That could mean raw session
transcripts, or a curated log of the significant prompts with the reasoning behind them.

> **Working assumption:** a curated log — the prompts that actually shaped the design, what I
> accepted, what I rejected and why. I think the rejections are the more useful signal, so those are
> recorded too. Raw transcripts are available if you would prefer them.

**Answer:** The curated log is sufficient. "You may include prompts that influenced the design and
relevant decisions/rejections."

**What I did with that.** Confirms the shape I planned, including the rejections.

---

### 11. Any preference on the video demo — length and focus?

> **Working assumption:** a short walkthrough of the working software from the HR Manager's point of
> view, followed by a brief tour of the design decisions.

**Answer:** Not addressed in the reply. Proceeding on the working assumption.
