-- =============================================================================
-- 03_transform_load_dw.sql  |  staging -> typed star schema (idempotent, one transaction)
--
-- Transformations applied (each is documented in docs/DATA_DICTIONARY.md):
--   1. Drop 19 constant metadata columns (they carry no information).
--   2. Split the SDMX "code + _LABEL" pairs into conformed dimensions.
--   3. Repair mojibake in area names (double-encoded UTF-8, e.g. 'Ã©' -> 'é').
--   4. Normalise whitespace in indicator names.
--   5. Classify areas as country_or_territory vs aggregate.
--   6. Cast OBS_VALUE to numeric; empty string -> NULL (status 'O' = missing).
-- =============================================================================
\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION staging.fix_mojibake(t text) RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF t ~ '[\u00C3\u00C2]' THEN
        BEGIN
            RETURN convert_from(convert_to(t, 'LATIN1'), 'UTF8');
        EXCEPTION WHEN OTHERS THEN
            RETURN t;            -- not actually double-encoded: leave untouched
        END;
    END IF;
    RETURN t;
END $$;

BEGIN;

TRUNCATE dw.fact_observation, dw.dim_area, dw.dim_indicator, dw.dim_breakdown,
         dw.dim_urbanisation, dw.dim_year, dw.dim_obs_status RESTART IDENTITY;

-- ---- dimensions -------------------------------------------------------------
INSERT INTO dw.dim_area (iso3, area_name, area_type)
SELECT s.ref_area,
       staging.fix_mojibake(min(s.ref_area_label)),
       CASE WHEN s.ref_area IN ('WLD','SSF','SAS','LCN','NAC')
            THEN 'aggregate' ELSE 'country_or_territory' END
FROM staging.se4all_raw s
GROUP BY s.ref_area
ORDER BY s.ref_area;

INSERT INTO dw.dim_indicator (indicator_code, indicator_name, unit_code, unit_name, unit_type,
                              unit_multiplier, agg_method, theme, sdg_indicator)
SELECT s.indicator,
       regexp_replace(btrim(min(s.indicator_label)), '\s+', ' ', 'g'),
       min(s.unit_measure), min(s.unit_measure_label), min(s.unit_type),
       min(s.unit_mult)::integer, min(s.agg_method),
       CASE s.indicator
            WHEN 'WB_SE4ALL_EG_ACS_ELEC'  THEN 'Energy access'
            WHEN 'WB_SE4ALL_EG_EGY_CLEAN' THEN 'Energy access'
            WHEN 'WB_SE4ALL_EG_EGEN_RNEW' THEN 'Renewable energy'
            WHEN 'WB_SE4ALL_EG_FEC_RNEW'  THEN 'Renewable energy'
            WHEN 'WB_SE4ALL_EG_FCON_RNEW' THEN 'Renewable energy'
            WHEN 'WB_SE4ALL_EG_FEC_TOT'   THEN 'Energy efficiency'
            WHEN 'WB_SE4ALL_EG_INT_LVL'   THEN 'Energy efficiency'
            WHEN 'WB_SE4ALL_EG_INFLW_IC'  THEN 'Finance'
            ELSE 'Other' END,
       CASE s.indicator
            WHEN 'WB_SE4ALL_EG_ACS_ELEC'  THEN '7.1.1'
            WHEN 'WB_SE4ALL_EG_EGY_CLEAN' THEN '7.1.2'
            WHEN 'WB_SE4ALL_EG_FEC_RNEW'  THEN '7.2.1'
            WHEN 'WB_SE4ALL_EG_INT_LVL'   THEN '7.3.1'
            WHEN 'WB_SE4ALL_EG_INFLW_IC'  THEN '7.a.1'
            WHEN 'WB_SE4ALL_EG_EGEN_RNEW' THEN '7.b.1'
            ELSE NULL END
FROM staging.se4all_raw s
GROUP BY s.indicator
ORDER BY s.indicator;

INSERT INTO dw.dim_breakdown (breakdown_code, breakdown_label, breakdown_family)
SELECT s.comp_breakdown_1,
       min(s.comp_breakdown_1_label),
       CASE WHEN s.comp_breakdown_1 = '_Z'                           THEN 'NONE'
            WHEN s.comp_breakdown_1 LIKE 'WB\_SE4ALL\_RENEWSRC\_%'   THEN 'RENEWABLE_SOURCE'
            WHEN s.comp_breakdown_1 LIKE 'WB\_SE4ALL\_TYPE\_%'       THEN 'ENERGY_USE_TYPE'
            ELSE 'NONE' END
FROM staging.se4all_raw s
GROUP BY s.comp_breakdown_1
ORDER BY s.comp_breakdown_1;

INSERT INTO dw.dim_urbanisation (urb_code, urb_label)
SELECT s.urbanisation, min(s.urbanisation_label)
FROM staging.se4all_raw s GROUP BY s.urbanisation ORDER BY s.urbanisation;

INSERT INTO dw.dim_obs_status (status_code, status_label)
SELECT s.obs_status, min(s.obs_status_label)
FROM staging.se4all_raw s GROUP BY s.obs_status ORDER BY s.obs_status;

INSERT INTO dw.dim_year (year, decade)
SELECT y::smallint, (y / 10 * 10)::smallint
FROM generate_series((SELECT min(time_period::int) FROM staging.se4all_raw),
                     (SELECT max(time_period::int) FROM staging.se4all_raw)) AS y;

-- ---- fact ---------------------------------------------------------------------
INSERT INTO dw.fact_observation
       (area_key, indicator_key, breakdown_key, urb_key, year, obs_value, status_code)
SELECT a.area_key, i.indicator_key, b.breakdown_key, u.urb_key,
       s.time_period::smallint,
       NULLIF(btrim(s.obs_value), '')::numeric,
       s.obs_status
FROM staging.se4all_raw s
JOIN dw.dim_area         a ON a.iso3           = s.ref_area
JOIN dw.dim_indicator    i ON i.indicator_code = s.indicator
JOIN dw.dim_breakdown    b ON b.breakdown_code = s.comp_breakdown_1
JOIN dw.dim_urbanisation u ON u.urb_code       = s.urbanisation;

-- ---- reconciliation: nothing silently lost or duplicated by the joins ---------
DO $$
DECLARE n_in bigint; n_out bigint;
BEGIN
    SELECT count(*) INTO n_in  FROM staging.se4all_raw;
    SELECT count(*) INTO n_out FROM dw.fact_observation;
    INSERT INTO audit.etl_run_log (step, rows_in, rows_out) VALUES ('03_transform_load_dw', n_in, n_out);
    IF n_in <> n_out THEN
        RAISE EXCEPTION 'Row reconciliation failed: staging=% fact=%', n_in, n_out;
    END IF;
    RAISE NOTICE 'Reconciled % rows staging -> fact', n_out;
END $$;

COMMIT;
