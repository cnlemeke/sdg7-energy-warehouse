# Physical design and query plans

This page records what the plans in `sql/10_performance.sql` show. It does not claim a speed gain.

## What was run

| Item | Value |
|---|---|
| PostgreSQL | 16.15 |
| Data | the committed 13-area sample, 7,801 fact rows |
| Command | `psql -f sql/10_performance.sql` after `sql/run_all.sql` |

At 7,801 rows every query finishes in under a millisecond, so timings say nothing about speed at scale. The plans do show that the planner uses the structures the design intends. Re-run the script on the full file (about 144,000 rows) and add those plans here if you want a size that matters.

## What the plans show

| Query | Design feature | What the plan shows |
|---|---|---|
| P1 `WHERE year >= 2015` | `RANGE (year)` partitions by decade | Only `fact_observation_2010s` and `fact_observation_2020s` are scanned. The 1990s and 2000s partitions are pruned. |
| P2 one country over time | index `ix_fact_area_year` | A bitmap index scan on the area-and-year index in each partition. There is no year filter, so all four partitions are read, as expected. |
| P3 one indicator in one year | index `ix_fact_year_indicator` | Only the 2020s partition is touched, through the year and indicator index. |
| P4 latest values for one country | materialised view `mart.mv_country_scorecard` | A scan of 13 rows. The planner prefers a sequential scan on a table this small, so the unique index is not used. |

## How to read this

Partitioning and the extra indexes are patterns that pay off on large tables. Here they are shown to work, not shown to help. The partial index `ix_fact_nonnull_value` is created but none of the four plans uses it.
