# Performance

Every number here was measured against the full 10,000-employee seed. Where a claim elsewhere in the
repository turned out to disagree with the measurement, the measurement won and the claim was
changed — two such corrections are recorded in §6.

## 1. How this was measured

| | |
| --- | --- |
| Hardware | 4 cores, 7 GB RAM, SSD. A developer laptop, not a server. |
| Postgres | 12.22, `shared_buffers` 128 MB, `work_mem` 4 MB — stock Ubuntu packaging |
| Dataset | 10,000 employees, 40,489 compensation records, 10 departments, 10 countries, 54 exchange rates |
| Method | Query objects called directly, outside HTTP, so the figures are the database and the Ruby that wraps it rather than the router and the JSON encoder |
| Repetition | Cold run reported separately, then 10 runs with p50 / p95 / min |

**The query cache had to be turned off to get honest numbers.** `rails runner` wraps a script in an
executor that enables the ActiveRecord query cache, which turns the second and subsequent runs of an
identical query into a hash lookup. Under it, every query in this table measured 1–4 ms and the
numbers were uniform in a way that should have been suspicious. Wrapping the benchmark in
`ActiveRecord::Base.uncached` moved the directory's median from 4.0 ms to 11.3 ms. The first set of
figures was measuring Ruby; only the second measures Postgres.

Table and index sizes:

| Table | Rows | Table size | Index size |
| --- | --- | --- | --- |
| `compensations` | 40,489 | 5.2 MB | 7.0 MB |
| `employees` | 10,000 | 1.7 MB | 3.2 MB |
| `exchange_rates` | 54 | 40 kB | 40 kB |

The whole dataset is about 17 MB against 128 MB of `shared_buffers`, so after the first touch it is
resident in memory. Every plan below reports `Buffers: shared hit=…` with no `read=`: there is no
disk I/O in these figures, and at this scale there would not be in production either. That is a fact
about the size of the problem, and it is the main reason no caching layer is warranted.

## 2. End-to-end, query cache off (milliseconds)

| Operation | Cold | p50 | p95 | min |
| --- | ---: | ---: | ---: | ---: |
| Directory, default page 1 | 74.0 | **11.3** | 13.1 | 9.6 |
| Directory, page 200 | 23.8 | 21.7 | 23.1 | 19.1 |
| Directory, `page_size=100` | 15.0 | 15.4 | 16.3 | 14.2 |
| Directory, search `q=ana` | 9.7 | 9.9 | 12.1 | 6.3 |
| Directory, search `q=priya` | 10.2 | 7.8 | 9.7 | 5.9 |
| Directory, filter `country=IN` (2,116 people) | 7.8 | 8.9 | 9.9 | 7.4 |
| Directory, sort by salary desc | 22.3 | 19.5 | 19.9 | 17.2 |
| Directory, sort by salary, page 100 | 18.6 | 20.4 | 21.9 | 18.5 |
| Directory, `status=departed` | 7.8 | 7.4 | 8.6 | 5.4 |
| Payroll summary, whole company | 19.3 | **16.2** | 16.5 | 15.8 |
| Payroll summary, filtered to one country | 14.2 | 13.2 | 14.3 | 12.4 |
| Payroll summary, `as_of` two years ago | 16.5 | 16.1 | 17.6 | 14.4 |
| Breakdown by country | 14.6 | 13.5 | 15.2 | 12.7 |
| Breakdown by department | 13.7 | 14.4 | 16.3 | 12.6 |
| Breakdown by job level | 13.2 | 13.5 | 15.3 | 12.9 |
| CSV export, whole directory (9,565 rows, 1.36 MB) | 287.2 | 238.9 | — | 237.3 |

The success criterion was "well under a second". The interactive surfaces are one to two orders of
magnitude inside it; the export is the only operation measured in hundreds of milliseconds, and §5
explains why that is Ruby rather than Postgres.

**Cold is the first call in the process, not the first call ever.** The 74 ms on the directory's
first row is ActiveRecord loading and warming — model schema reflection, prepared-statement setup —
not Postgres reading from disk. The plan for that same query executes in 3.5 ms.

## 3. Statements per operation

An operation's cost is partly how many round trips it makes. Nothing here grows with the number of
rows on the page, which is the property that matters:

| Operation | Statements | What they are |
| --- | ---: | --- |
| Directory page | 5 | count, the page, then departments, compensations and currencies preloaded in bulk |
| Directory page sorted by salary | 4 | as above; the count is folded into the join |
| Payroll summary | 3 | aggregate, histogram, base currency |
| Breakdown by department | 2 | aggregate, then department names resolved in one lookup |
| CSV export, 9,565 rows | 2 | one `pluck`, one currency lookup |

Twenty-five employees on a page cost the same five statements as one hundred. The bulk lookups are
guarded by tests tagged `:n_plus_one`, and each guard was confirmed to fail when the bulk load is
replaced with a per-row one — a test that cannot fail is worse than no test.

## 4. Where the time goes

### Search is the best-behaved query in the system

The `pg_trgm` GIN index on the concatenated name/email/number expression (ADR-7):

```
Limit  (actual time=0.403..0.405 rows=25 loops=1)
  Buffers: shared hit=133
  ->  Sort  Sort Method: top-N heapsort  Memory: 35kB
        ->  Bitmap Heap Scan on employees  (actual time=0.034..0.338 rows=215 loops=1)
              ->  Bitmap Index Scan on index_employees_on_searchable_text
                    (actual time=0.020..0.020 rows=227 loops=1)
                    Buffers: shared hit=3
 Execution Time: 0.422 ms
```

Three buffers touched to find 227 candidate rows out of 10,000, and 0.42 ms end to end in the
database. A trigram index is what makes a leading-wildcard `ILIKE '%ana%'` an index scan instead of
the sequential scan it would otherwise force. The remaining ~9 ms of the measured 9.9 ms is Ruby
building 25 model objects and their associations.

Attribute filters behave the same way — `country_code` at 0.85 ms and `job_level` at 0.68 ms, both
bitmap index scans.

### The default page sequentially scans employees, and that is correct

```
Limit  (actual time=3.512..3.514 rows=25 loops=1)
  ->  Sort  Sort Key: last_name, first_name, id
        Sort Method: top-N heapsort  Memory: 36kB
        ->  Seq Scan on employees  (actual time=0.012..1.775 rows=9565 loops=1)
              Rows Removed by Filter: 435
              Buffers: shared hit=205
 Execution Time: 3.544 ms
```

No index on `(last_name, first_name)`, and none added. The unfiltered directory has to consider
every active employee whatever the access path, 205 buffers is the entire table, and a top-N
heapsort keeps only 25 rows in 36 kB. An index here would save perhaps a millisecond on reads and be
maintained on every write. Adding it would be indexing for appearance.

### Deep pagination is the real degradation

Page 200 costs 11.2 ms against page 1's 3.5 ms, and the plan says exactly why: the sort method
changes from `top-N heapsort  Memory: 36kB` to `quicksort  Memory: 2870kB`, materialising 5,000 rows
to discard 4,975 of them. `OFFSET` makes the database do work proportional to how far in you are.

Left as is, deliberately. The directory is a search-and-filter surface — the realistic path to the
400th page is that someone is scrolling because search did not give them what they wanted, which is
a product problem, not a query problem. Keyset pagination would fix the cost but breaks "jump to
page N" and is awkward across four sortable columns with NULLs. The cap on `page_size` bounds the
damage.

### The salary sort is a join, and no index removes that

```
Limit  (actual time=11.405..11.409 rows=25 loops=1)
  ->  Sort  Sort Method: top-N heapsort  Memory: 35kB
        ->  Hash Right Join  (actual time=3.231..9.102 rows=9565 loops=1)
              ->  Seq Scan on compensations  (actual time=0.014..3.805 rows=9565 loops=1)
                    Filter: effective_from <= … AND (effective_to IS NULL OR effective_to > …)
                    Rows Removed by Filter: 30,924
                    Buffers: shared hit=646
 Execution Time: 11.435 ms
```

Sorting 9,565 people by pay requires knowing all 9,565 salaries, so the join happens in full before
`LIMIT 25` can mean anything. The scan discards 30,924 of 40,489 compensation rows — the cost of
keeping history, paid on every query that needs today's pay. §6 records the index that was added to
avoid this and did not.

### Analytics aggregate in one pass each

The summary's headline figures — count, sum, mean, min, max and five percentiles — are a single
statement:

```
Aggregate  (actual time=7.565..7.567 rows=1 loops=1)
  ->  Hash Join  (actual time=1.302..5.918 rows=9565 loops=1)
        ->  Seq Scan on compensations  Rows Removed by Filter: 30924
        ->  Hash  ->  Index Only Scan using employees_pkey  Heap Fetches: 0
 Execution Time: 7.609 ms
```

The histogram is a second statement at 7.3 ms, and `width_bucket` does the bucketing inside the
`GROUP BY` so the nine bands come back as nine rows rather than 9,565 amounts crossing into Ruby to
be sorted. Together they are the 16 ms in the table above.

`Heap Fetches: 0` on the employees side is the filter subquery being answered entirely from the
primary key index. Filtering the population *narrows* the work — one country is 13.2 ms against the
whole company's 16.2 ms — so the expensive case is the default one, which is the right way round.

Breakdown by country is 12.5 ms and adds a `GroupAggregate` with an 833 kB quicksort, because
`percentile_cont` needs each group's values ordered. Ten groups with seven aggregates each, in one
statement.

### `as_of` is free

Asking for two years ago costs 16.1 ms against today's 16.2 ms. The query was already date-scoped, so
history is not a second code path with a second performance profile. This is the effective-dated
model paying for itself.

## 5. The CSV export is Ruby, not Postgres

| Phase | Time |
| --- | ---: |
| SQL execution (`EXPLAIN ANALYZE`) | 28.6 ms |
| `pluck` including result transfer into Ruby | 92 ms |
| `CSV.generate` — 9,565 rows, formula-escaping, minor-to-major conversion | ~147 ms |
| **Total** | **239 ms** |

Postgres contributes 12% of the wall clock. Optimising the query would be optimising the part that
is already fast; the time is in building 1.36 MB of string in Ruby.

The export uses `pluck` rather than model instantiation, so 9,565 employees with their pay are
scalars rather than ~19,000 ActiveRecord objects. Response is built as one string rather than
streamed: streaming would hold a connection for the duration and make it impossible to report an
error once the headers are out, in exchange for latency that is already a quarter of a second. That
trade flips in the hundreds of thousands of rows.

## 6. Two claims that measurement removed

Recorded because being wrong in public is the point of writing measurements down.

**An index that had never been scanned.** `index_current_compensations_on_base_amount` was added on
the assumption that the directory's sort-by-pay would walk it in order. It never did: the plan is a
hash join followed by a top-N heapsort whether or not the index exists — 10.2 ms with it, 9.9 ms
without — and `pg_stat_user_indexes` reported zero scans across the database's entire lifetime,
including the seed. It was 312 kB kept current on every compensation write, and a claim in the schema
that pay was indexed for sorting when it was not. Dropped in a reversible migration.

**A "warm" figure that was a cache artefact.** The payroll summary was recorded in an earlier draft
at 1.2–1.7 ms warm. That was the ActiveRecord query cache returning a memoised result, not Postgres
answering. The honest figure is 16.2 ms, an order of magnitude slower and still comfortably inside
the requirement. The benchmark now runs inside `ActiveRecord::Base.uncached`.

## 7. Open observations

**Zero scans means "never exercised", not "useless".** Three indexes report zero scans and are
staying: `employees_pkey` on email and employee number enforce uniqueness rather than serve reads,
and `index_employees_on_job_level` showed zero until a job-level filter was benchmarked, at which
point it was used and took the query to 0.68 ms. The counter is a prompt to check the plan, not a
verdict. That distinction is precisely why the index in §6 was dropped on plan evidence rather than
on the counter alone.

**One index is still a candidate.** `index_employees_on_active` — a partial index on `id` where
`ended_on IS NULL` — is not used by the directory's active filter, because that filter is
`hired_on <= today AND (ended_on IS NULL OR ended_on >= today)` and the `OR` branch does not match
the partial predicate. The planner chooses a sequential scan. Not dropped yet: unlike the §6 case it
is small and the predicate is at least coherent with a query someone might write. Flagged rather than
acted on.

## 8. What changes at 10× and 100×

| Scale | What breaks first | What I would do |
| --- | --- | --- |
| 100,000 | Nothing, on these plans. The sequential scans triple in cost and stay in single-digit milliseconds. Deep pagination gets worse in proportion. | Nothing. Re-measure. |
| 1,000,000 | Analytics scan compensations in full on every request, so the summary moves into the hundreds of milliseconds. CSV export exceeds a request timeout. | Keyset pagination; a nightly rollup table of current pay per employee so analytics stop scanning history; move export to a background job with a download link. |
| 10,000,000 | The rollup itself becomes the expensive thing. | Partition `compensations` by effective date; pre-aggregate per country/department/level. |

None of this is built. At the stated target of 10,000 employees the system is roughly two orders of
magnitude inside its budget, and the structure that would make the first step cheap — aggregation
already in SQL, filters already shared between the directory and analytics, no endpoint loading the
dataset into memory — is in place.

## 9. Reproducing this

The benchmark harness is not committed: it is a throwaway script, and a committed benchmark that
nobody runs decays into another unverified claim. To regenerate, call the query objects inside
`ActiveRecord::Base.uncached`, subscribe to `sql.active_record` for statement counts, and run
`EXPLAIN (ANALYZE, BUFFERS)` on `relation.to_sql`. The seed is deterministic, so the population
figures above — 9,565 active employees, 40,489 compensation records — should reproduce exactly.
