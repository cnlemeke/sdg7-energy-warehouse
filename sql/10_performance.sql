-- =============================================================================
-- 10_performance.sql  |  Evidence that the physical design works.
-- Run with:  psql -f sql/10_performance.sql  and keep the plans in docs/PERFORMANCE.md
-- =============================================================================

-- P1 Partition pruning: only the 2010s and 2020s partitions should appear in the plan.
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM dw.fact_observation WHERE year >= 2015;

-- P2 Country time-series lookup should use ix_fact_area_year (index scan, not seq scan).
EXPLAIN (ANALYZE, BUFFERS)
SELECT year, obs_value
FROM dw.fact_observation f JOIN dw.dim_area a USING (area_key)
WHERE a.iso3 = 'KEN' AND f.obs_value IS NOT NULL ORDER BY year;

-- P3 Cross-section for one indicator-year should use ix_fact_year_indicator.
EXPLAIN (ANALYZE, BUFFERS)
SELECT area_key, obs_value FROM dw.fact_observation
WHERE year = 2022 AND indicator_key = 1;

-- P4 Compare view vs materialised scorecard for the same "latest values" question.
EXPLAIN (ANALYZE) SELECT * FROM mart.mv_country_scorecard WHERE iso3 = 'IND';
