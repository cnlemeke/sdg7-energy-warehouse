-- =============================================================================
-- 05_data_quality.sql  |  Declarative data-quality rules as one queryable view
--   severity ERROR -> pipeline must fail  |  WARN/INFO -> documented source anomalies
-- Usage:   SELECT * FROM dq.check_results ORDER BY severity, check_id;
--          SELECT dq.assert_clean();      -- raises if any ERROR rule has failed rows
-- Tolerances were derived empirically from the full dataset (see docs/DATA_DICTIONARY.md)
-- =============================================================================
\set ON_ERROR_STOP on

CREATE OR REPLACE VIEW dq.check_results AS
-- DQ01 reconciliation: every staged row must exist exactly once in the fact table
SELECT 'DQ01' AS check_id, 'ERROR' AS severity,
       'staging rows not reconciled with fact rows' AS description,
       ABS((SELECT COUNT(*) FROM staging.se4all_raw) - (SELECT COUNT(*) FROM dw.fact_observation)) AS failed_rows
UNION ALL
-- DQ02 grain: duplicate natural keys in the raw feed
SELECT 'DQ02', 'ERROR', 'duplicate natural keys in staging',
       (SELECT COUNT(*) FROM (
            SELECT 1 FROM staging.se4all_raw
            GROUP BY ref_area, indicator, comp_breakdown_1, urbanisation, time_period
            HAVING COUNT(*) > 1) d)
UNION ALL
-- DQ03 percentages must lie in [0, 100]
SELECT 'DQ03', 'ERROR', 'percentage indicators outside 0-100',
       (SELECT COUNT(*) FROM dw.fact_observation f
          JOIN dw.dim_indicator i ON i.indicator_key = f.indicator_key
         WHERE i.unit_code = 'PT' AND (f.obs_value < 0 OR f.obs_value > 100))
UNION ALL
-- DQ04 no negative values anywhere (all SE4ALL series are non-negative by definition)
SELECT 'DQ04', 'ERROR', 'negative observation values',
       (SELECT COUNT(*) FROM dw.fact_observation WHERE obs_value < 0)
UNION ALL
-- DQ05 one indicator code must map to exactly one label (else dim build is ambiguous)
SELECT 'DQ05', 'ERROR', 'indicator codes with more than one label',
       (SELECT COUNT(*) FROM (
            SELECT indicator FROM staging.se4all_raw
            GROUP BY indicator HAVING COUNT(DISTINCT indicator_label) > 1) x)
UNION ALL
-- DQ06 encoding repair worked: no area name may still contain the mojibake lead bytes
SELECT 'DQ06', 'ERROR', 'area names still containing mojibake',
       (SELECT COUNT(*) FROM dw.dim_area WHERE area_name LIKE '%' || CHR(195) || '%')
UNION ALL
-- DQ07 additivity: installed renewable capacity, ALLRENEW = sum of source components (+-2.5 W/capita rounding)
SELECT 'DQ07', 'ERROR', 'capacity: all-renewables != sum of sources (tol 2.5 W/capita)',
       (SELECT COUNT(*) FROM (
            SELECT f.area_key, f.year,
                   MAX(f.obs_value) FILTER (WHERE b.breakdown_code =  'WB_SE4ALL_RENEWSRC_ALLRENEW') AS total,
                   SUM(f.obs_value) FILTER (WHERE b.breakdown_code <> 'WB_SE4ALL_RENEWSRC_ALLRENEW') AS parts
              FROM dw.fact_observation f
              JOIN dw.dim_indicator i ON i.indicator_key = f.indicator_key
              JOIN dw.dim_breakdown b ON b.breakdown_key = f.breakdown_key
             WHERE i.indicator_code = 'WB_SE4ALL_EG_EGEN_RNEW'
             GROUP BY f.area_key, f.year) t
         WHERE t.total IS NOT NULL AND ABS(t.total - COALESCE(t.parts, 0)) > 2.5)
UNION ALL
-- DQ08 additivity: international financial flows, ALLRENEW = sum of sources incl. multiple (+-0.05 USD m)
SELECT 'DQ08', 'ERROR', 'finance: all-renewables != sum of sources (tol 0.05 USD m)',
       (SELECT COUNT(*) FROM (
            SELECT f.area_key, f.year,
                   MAX(f.obs_value) FILTER (WHERE b.breakdown_code =  'WB_SE4ALL_RENEWSRC_ALLRENEW') AS total,
                   SUM(f.obs_value) FILTER (WHERE b.breakdown_code <> 'WB_SE4ALL_RENEWSRC_ALLRENEW') AS parts
              FROM dw.fact_observation f
              JOIN dw.dim_indicator i ON i.indicator_key = f.indicator_key
              JOIN dw.dim_breakdown b ON b.breakdown_key = f.breakdown_key
             WHERE i.indicator_code = 'WB_SE4ALL_EG_INFLW_IC'
             GROUP BY f.area_key, f.year) t
         WHERE t.total IS NOT NULL AND ABS(t.total - COALESCE(t.parts, 0)) > 0.05)
UNION ALL
-- DQ09 logical subset: modern renewables share <= renewables share
SELECT 'DQ09', 'ERROR', 'modern-renewable share exceeds total renewable share',
       (SELECT COUNT(*) FROM (
            SELECT f.area_key, f.year,
                   MAX(f.obs_value) FILTER (WHERE b.breakdown_code = 'WB_SE4ALL_TYPE_RENEWBLS')    AS ren,
                   MAX(f.obs_value) FILTER (WHERE b.breakdown_code = 'WB_SE4ALL_TYPE_MDRNRENWBLS') AS modern
              FROM dw.fact_observation f
              JOIN dw.dim_indicator i ON i.indicator_key = f.indicator_key
              JOIN dw.dim_breakdown b ON b.breakdown_key = f.breakdown_key
             WHERE i.indicator_code = 'WB_SE4ALL_EG_FEC_RNEW'
             GROUP BY f.area_key, f.year) t
         WHERE t.ren IS NOT NULL AND t.modern IS NOT NULL AND t.modern > t.ren + 0.05)
UNION ALL
-- DQ10 (WARN) national total should lie between its urban and rural components (+-0.15 pp)
SELECT 'DQ10', 'WARN', 'electricity access: national total outside [min,max] of urban/rural',
       (SELECT COUNT(*) FROM (
            SELECT f.area_key, f.year,
                   MAX(f.obs_value) FILTER (WHERE u.urb_code = '_T')  AS tot,
                   MAX(f.obs_value) FILTER (WHERE u.urb_code = 'URB') AS urb,
                   MAX(f.obs_value) FILTER (WHERE u.urb_code = 'RUR') AS rur
              FROM dw.fact_observation f
              JOIN dw.dim_indicator i    ON i.indicator_key = f.indicator_key
              JOIN dw.dim_urbanisation u ON u.urb_key = f.urb_key
             WHERE i.indicator_code = 'WB_SE4ALL_EG_ACS_ELEC'
             GROUP BY f.area_key, f.year) t
         WHERE t.tot IS NOT NULL AND t.urb IS NOT NULL AND t.rur IS NOT NULL
           AND (t.tot < CASE WHEN t.urb < t.rur THEN t.urb ELSE t.rur END - 0.15
             OR t.tot > CASE WHEN t.urb > t.rur THEN t.urb ELSE t.rur END + 0.15))
UNION ALL
-- DQ11 (INFO) rural access higher than urban access (counter-intuitive but reported by source)
SELECT 'DQ11', 'INFO', 'electricity access: rural > urban observations',
       (SELECT COUNT(*) FROM (
            SELECT f.area_key, f.year,
                   MAX(f.obs_value) FILTER (WHERE u.urb_code = 'URB') AS urb,
                   MAX(f.obs_value) FILTER (WHERE u.urb_code = 'RUR') AS rur
              FROM dw.fact_observation f
              JOIN dw.dim_indicator i    ON i.indicator_key = f.indicator_key
              JOIN dw.dim_urbanisation u ON u.urb_key = f.urb_key
             WHERE i.indicator_code = 'WB_SE4ALL_EG_ACS_ELEC'
             GROUP BY f.area_key, f.year) t
         WHERE t.urb IS NOT NULL AND t.rur IS NOT NULL AND t.rur > t.urb)
UNION ALL
-- DQ12 (INFO) missing observations flagged by the publisher (status O)
SELECT 'DQ12', 'INFO', 'observations flagged missing by source (status O)',
       (SELECT COUNT(*) FROM dw.fact_observation WHERE status_code = 'O');

CREATE OR REPLACE FUNCTION dq.assert_clean() RETURNS text
LANGUAGE plpgsql AS $$
DECLARE bad text;
BEGIN
    SELECT string_agg(check_id || ' (' || failed_rows || ' rows): ' || description, E'\n')
      INTO bad
      FROM dq.check_results
     WHERE severity = 'ERROR' AND failed_rows > 0;
    IF bad IS NOT NULL THEN
        RAISE EXCEPTION E'Data-quality ERROR rules failed:\n%', bad;
    END IF;
    RETURN 'All ERROR-level data-quality rules passed';
END $$;

SELECT * FROM dq.check_results ORDER BY severity, check_id;
