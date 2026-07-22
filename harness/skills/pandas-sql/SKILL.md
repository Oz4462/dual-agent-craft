---
name: pandas-sql
description: Data work discipline — pandas without silent corruption, SQL without injection or table-scans, results with row-count sanity checks.
---
# Pandas + SQL

## Pandas rules
- `.loc[mask, col] = value` for writes — never chained assignment; treat the SettingWithCopy warning as an error.
- Vectorize; `itertuples` only when unavoidable; never mutate while iterating.
- Every merge: check row counts before/after + `validate=` argument (`one_to_one`, `one_to_many`) — silent fan-out is the classic corruption.
- NaN discipline: decide explicitly (drop/fill/keep) per column, document why; `dropna()` without args is a data-loss grenade.
- dtypes pinned at load (`dtype=`, `parse_dates=`); a numeric column arriving as object is a bug at the source.

## SQL rules
- Parameterized queries ONLY — string-built SQL is banned even for "internal" values.
- Exploratory queries carry `LIMIT`; production queries carry an index plan (`EXPLAIN` before shipping anything joining >2 tables).
- Multi-statement mutations in a transaction; migrations reversible or explicitly marked one-way.
- N+1 killed by JOIN/batch; SELECT lists explicit (no `*` in shipped code).

## Sanity gate (every analysis)
Row counts at each pipeline stage logged; totals reconciled against a known anchor; one spot-check by hand before conclusions ship.
