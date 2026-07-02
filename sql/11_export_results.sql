-- =============================================================================
-- 11_export_results.sql  |  Export the semantic layer for python/make_figures.py
-- Output folder: set out_dir, default results. The folder must already exist.
--   psql -v out_dir=results/sample -f sql/11_export_results.sql
-- psql does not expand variables inside \copy, so each command is built first.
-- =============================================================================
\set ON_ERROR_STOP on
\if :{?out_dir}
\else
  \set out_dir results
\endif

\set copy_cy '\\copy (SELECT * FROM mart.v_country_year ORDER BY iso3, year) TO ''' :out_dir '/country_year.csv'' WITH (FORMAT csv, HEADER true)'
:copy_cy
\set copy_dq '\\copy (SELECT * FROM dq.check_results ORDER BY severity, check_id) TO ''' :out_dir '/dq_check_results.csv'' WITH (FORMAT csv, HEADER true)'
:copy_dq
