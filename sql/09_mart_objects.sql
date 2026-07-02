-- =============================================================================
-- 09_mart_objects.sql  |  Materialised scorecard, reusable function, role-based access
-- =============================================================================
\set ON_ERROR_STOP on

-- Latest-value country scorecard (DISTINCT ON picks the newest non-null per metric).
DROP MATERIALIZED VIEW IF EXISTS mart.mv_country_scorecard;
CREATE MATERIALIZED VIEW mart.mv_country_scorecard AS
WITH e AS (SELECT DISTINCT ON (iso3) iso3, year AS elec_year, elec_access_pct
           FROM mart.v_country_year WHERE elec_access_pct IS NOT NULL ORDER BY iso3, year DESC),
     c AS (SELECT DISTINCT ON (iso3) iso3, year AS cook_year, clean_cooking_pct
           FROM mart.v_country_year WHERE clean_cooking_pct IS NOT NULL ORDER BY iso3, year DESC),
     r AS (SELECT DISTINCT ON (iso3) iso3, year AS ren_year, renewable_share_pct
           FROM mart.v_country_year WHERE renewable_share_pct IS NOT NULL ORDER BY iso3, year DESC),
     e10 AS (SELECT iso3, elec_access_pct AS elec_2010
           FROM mart.v_country_year WHERE year = 2010)
SELECT a.iso3, a.area_name, a.area_type,
       e.elec_year, e.elec_access_pct, e10.elec_2010,
       e.elec_access_pct - e10.elec_2010 AS elec_gain_since_2010_pp,
       c.cook_year, c.clean_cooking_pct,
       r.ren_year,  r.renewable_share_pct
FROM dw.dim_area a
LEFT JOIN e   ON e.iso3 = a.iso3
LEFT JOIN c   ON c.iso3 = a.iso3
LEFT JOIN r   ON r.iso3 = a.iso3
LEFT JOIN e10 ON e10.iso3 = a.iso3;
CREATE UNIQUE INDEX ux_scorecard_iso3 ON mart.mv_country_scorecard (iso3);
-- Refresh without blocking readers:  REFRESH MATERIALIZED VIEW CONCURRENTLY mart.mv_country_scorecard;

-- Reusable, parameterised access path for applications / notebooks.
CREATE OR REPLACE FUNCTION mart.fn_country_profile(p_iso3 text)
RETURNS SETOF mart.v_country_year
LANGUAGE sql STABLE AS $$
    SELECT * FROM mart.v_country_year WHERE iso3 = upper(p_iso3) ORDER BY year;
$$;

-- Least-privilege read-only role for analysts / BI tools (no access to staging or audit).
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'se4all_reader') THEN
        CREATE ROLE se4all_reader NOLOGIN;
    END IF;
END $$;
GRANT USAGE ON SCHEMA dw, mart, dq TO se4all_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA dw, mart, dq TO se4all_reader;
GRANT EXECUTE ON FUNCTION mart.fn_country_profile(text) TO se4all_reader;
REVOKE ALL ON SCHEMA staging, audit FROM se4all_reader;
