# Clarifying Questions

Sent to the Incubyte team before building. Each question carries the assumption I proceeded on, so
that work continued without blocking on a reply. Answers are recorded inline as they arrive.

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

**Answer:** _pending_

---

### 2. Is salary *history* in scope, or only each employee's current salary?

This is the single biggest driver of the data model. History means compensation is an
effective-dated, append-only series rather than a column on the employee record.

> **Working assumption:** in scope. An HR manager asking "how do we pay people?" almost always also
> asks "and how has that changed?" Append-only records also mean a correction can never silently
> destroy the previous value. I have modelled it this way.

**Answer:** _pending_

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

**Answer:** _pending_

---

### 4. Should the HR Manager be able to apply bulk changes?

For example, "give everyone in Engineering in India a 6% increase." This is genuinely common in
annual review cycles, but it needs preview-before-apply and a way to undo, which is a meaningful
chunk of work.

> **Working assumption:** out of scope for this submission. Single-employee salary changes only. I
> have noted it as a natural next increment, since the append-only model already supports it
> cleanly.

**Answer:** _pending_

---

### 5. Do we track joiners and leavers?

It affects what "total payroll cost" means — whether it counts only currently active employees, and
whether someone who left mid-year still contributes to a historical figure.

> **Working assumption:** employees have a hire date and an optional end date. Analytics count
> active employees by default, and the UI states this explicitly so the number is never ambiguous.

**Answer:** _pending_

---

## Non-functional

### 6. Is authentication expected?

The brief names one persona with full access. Salary data is about as sensitive as internal data
gets, so I do not want to appear casual about it.

> **Working assumption:** out of scope, and documented as the first thing to add before real use.
> My reasoning is that a single-role login would consume build time without exercising any of the
> interesting parts of this domain. Happy to add it if you would rather see it.

**Answer:** _pending_

---

### 7. Is 10,000 employees the target, or a starting point?

It changes what "good performance" means. At 10,000 rows, correct indexing and aggregation in SQL
are sufficient. At 1,000,000, I would be looking at materialised rollups for the analytics views.

> **Working assumption:** 10,000 is the real target. I am designing so the system does not fall over
> beyond that — all aggregation happens in SQL rather than in Ruby, and nothing loads the full
> dataset into memory — but I am not pre-building rollup infrastructure for a scale you have not
> asked for.

**Answer:** _pending_

---

## Logistics

### 8. What is the deadline, and roughly what time investment do you expect?

I would rather calibrate depth to your expectations than over- or under-build.

> **Working assumption:** proceeding at a scope I can deliver to a high standard.

**Answer:** _pending_

---

### 9. For "fully functional deployed software" — is a free-tier public URL acceptable?

And does it need to remain live through the interview rounds?

> **Working assumption:** yes, a public URL on a free tier, kept live through the process.

**Answer:** _pending_

---

### 10. In what form would you like the AI artifacts?

You have asked for "prompts or instructions used with AI tools." That could mean raw session
transcripts, or a curated log of the significant prompts with the reasoning behind them.

> **Working assumption:** a curated log — the prompts that actually shaped the design, what I
> accepted, what I rejected and why. I think the rejections are the more useful signal, so those are
> recorded too. Raw transcripts are available if you would prefer them.

**Answer:** _pending_

---

### 11. Any preference on the video demo — length and focus?

> **Working assumption:** a short walkthrough of the working software from the HR Manager's point of
> view, followed by a brief tour of the design decisions.

**Answer:** _pending_
