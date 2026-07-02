-- =============================================================================
-- 04_constraints_indexes.sql  |  Secondary indexes + planner statistics
-- The PK (indicator, area, breakdown, urb, year) already serves "one indicator,
-- all countries" scans. These cover the other dominant access paths.
-- =============================================================================
\set ON_ERROR_STOP on

-- country time-series lookups:  WHERE area_key = ? ORDER BY year
CREATE INDEX IF NOT EXISTS ix_fact_area_year      ON dw.fact_observation (area_key, year);
-- cross-section lookups:        WHERE year = ? AND indicator_key = ?
CREATE INDEX IF NOT EXISTS ix_fact_year_indicator ON dw.fact_observation (year, indicator_key);
-- partial index: only the analytically useful (non-missing) rows
CREATE INDEX IF NOT EXISTS ix_fact_nonnull_value  ON dw.fact_observation (indicator_key, obs_value)
    WHERE obs_value IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_area_type           ON dw.dim_area (area_type);

ANALYZE dw.fact_observation;
ANALYZE dw.dim_area;
ANALYZE dw.dim_indicator;
