-- =============================================================================
-- 02_load_staging.sql  |  Bulk-load the raw CSV with client-side \copy
-- Run from the repository root so the relative path resolves.
-- Override the file with:  psql -v csv_path="'data/sample/WB_SE4ALL_sample.csv'" -f sql/02_load_staging.sql
-- =============================================================================
\set ON_ERROR_STOP on
\if :{?csv_path}
\else
  \set csv_path '''data/raw/WB_SE4ALL.csv'''
\endif

TRUNCATE staging.se4all_raw;
-- psql does not expand variables inside \copy, so build the command text first and then run it.
\set copycmd '\\copy staging.se4all_raw FROM ' :csv_path ' WITH (FORMAT csv, HEADER true, ENCODING ''UTF8'')'
:copycmd

INSERT INTO audit.etl_run_log (step, rows_in, rows_out)
SELECT '02_load_staging', NULL, count(*) FROM staging.se4all_raw;

SELECT count(*) AS staged_rows FROM staging.se4all_raw;
