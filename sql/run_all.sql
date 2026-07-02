-- =============================================================================
-- run_all.sql  |  The whole pipeline in one command. Works on any OS, with or
-- without Docker, because it only needs psql.
--
-- Run from the repository root so relative paths resolve.
--   Full data (data/raw/WB_SE4ALL.csv):
--     psql -d se4all -f sql/run_all.sql
--   Sample data, outputs kept apart from the committed results:
--     psql -d se4all -v csv_path="'data/sample/WB_SE4ALL_sample.csv'" -v out_dir=results/sample -f sql/run_all.sql
--
-- The out_dir folder must exist. Safe to run again: script 01 rebuilds every table.
-- =============================================================================
\set ON_ERROR_STOP on

\i sql/01_schema.sql
\i sql/02_load_staging.sql
\i sql/03_transform_load_dw.sql
\i sql/04_constraints_indexes.sql
\i sql/05_data_quality.sql
SELECT dq.assert_clean();
\i sql/06_views.sql
\i sql/07_analytics.sql
\i sql/08_postgres_advanced.sql
\i sql/09_mart_objects.sql
\i sql/10_performance.sql
\i sql/11_export_results.sql
