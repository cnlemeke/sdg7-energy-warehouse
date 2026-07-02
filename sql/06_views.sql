-- =============================================================================
-- 06_views.sql  |  Analyst-facing semantic layer (portable SQL)
--   mart.v_observation   fully denormalised fact (tidy long format)
--   mart.v_country_year  one row per area-year with headline indicators as columns
-- Pivot uses MAX() ... FILTER: the PK guarantees <= 1 source row per cell.
-- =============================================================================
\set ON_ERROR_STOP on

CREATE OR REPLACE VIEW mart.v_observation AS
SELECT a.iso3, a.area_name, a.area_type,
       i.indicator_code, i.indicator_name, i.unit_code, i.theme, i.sdg_indicator,
       b.breakdown_code, b.breakdown_label, b.breakdown_family,
       u.urb_code, y.year, y.decade,
       f.obs_value, f.status_code
FROM dw.fact_observation f
JOIN dw.dim_area         a ON a.area_key      = f.area_key
JOIN dw.dim_indicator    i ON i.indicator_key = f.indicator_key
JOIN dw.dim_breakdown    b ON b.breakdown_key = f.breakdown_key
JOIN dw.dim_urbanisation u ON u.urb_key       = f.urb_key
JOIN dw.dim_year         y ON y.year          = f.year;

CREATE OR REPLACE VIEW mart.v_country_year AS
SELECT a.iso3, a.area_name, a.area_type, f.year,
  MAX(f.obs_value) FILTER (WHERE i.indicator_code='WB_SE4ALL_EG_ACS_ELEC'  AND u.urb_code='_T')  AS elec_access_pct,
  MAX(f.obs_value) FILTER (WHERE i.indicator_code='WB_SE4ALL_EG_ACS_ELEC'  AND u.urb_code='URB') AS elec_access_urban_pct,
  MAX(f.obs_value) FILTER (WHERE i.indicator_code='WB_SE4ALL_EG_ACS_ELEC'  AND u.urb_code='RUR') AS elec_access_rural_pct,
  MAX(f.obs_value) FILTER (WHERE i.indicator_code='WB_SE4ALL_EG_EGY_CLEAN' AND u.urb_code='_T')  AS clean_cooking_pct,
  MAX(f.obs_value) FILTER (WHERE i.indicator_code='WB_SE4ALL_EG_EGY_CLEAN' AND u.urb_code='URB') AS clean_cooking_urban_pct,
  MAX(f.obs_value) FILTER (WHERE i.indicator_code='WB_SE4ALL_EG_EGY_CLEAN' AND u.urb_code='RUR') AS clean_cooking_rural_pct,
  MAX(f.obs_value) FILTER (WHERE i.indicator_code='WB_SE4ALL_EG_FEC_RNEW'  AND b.breakdown_code='WB_SE4ALL_TYPE_RENEWBLS')    AS renewable_share_pct,
  MAX(f.obs_value) FILTER (WHERE i.indicator_code='WB_SE4ALL_EG_FEC_RNEW'  AND b.breakdown_code='WB_SE4ALL_TYPE_MDRNRENWBLS') AS modern_renewable_share_pct,
  MAX(f.obs_value) FILTER (WHERE i.indicator_code='WB_SE4ALL_EG_FEC_TOT')   AS tfec_pj,
  MAX(f.obs_value) FILTER (WHERE i.indicator_code='WB_SE4ALL_EG_INT_LVL')   AS energy_intensity_mj_per_gdp,
  MAX(f.obs_value) FILTER (WHERE i.indicator_code='WB_SE4ALL_EG_EGEN_RNEW' AND b.breakdown_code='WB_SE4ALL_RENEWSRC_ALLRENEW') AS renew_capacity_w_pc,
  MAX(f.obs_value) FILTER (WHERE i.indicator_code='WB_SE4ALL_EG_EGEN_RNEW' AND b.breakdown_code='WB_SE4ALL_RENEWSRC_SLRERGY') AS solar_capacity_w_pc,
  MAX(f.obs_value) FILTER (WHERE i.indicator_code='WB_SE4ALL_EG_EGEN_RNEW' AND b.breakdown_code='WB_SE4ALL_RENEWSRC_WNDERGY') AS wind_capacity_w_pc,
  MAX(f.obs_value) FILTER (WHERE i.indicator_code='WB_SE4ALL_EG_EGEN_RNEW' AND b.breakdown_code='WB_SE4ALL_RENEWSRC_HYDPWR')  AS hydro_capacity_w_pc,
  MAX(f.obs_value) FILTER (WHERE i.indicator_code='WB_SE4ALL_EG_INFLW_IC'  AND b.breakdown_code='WB_SE4ALL_RENEWSRC_ALLRENEW') AS intl_flows_usd_m
FROM dw.fact_observation f
JOIN dw.dim_area         a ON a.area_key      = f.area_key
JOIN dw.dim_indicator    i ON i.indicator_key = f.indicator_key
JOIN dw.dim_breakdown    b ON b.breakdown_key = f.breakdown_key
JOIN dw.dim_urbanisation u ON u.urb_key       = f.urb_key
GROUP BY a.iso3, a.area_name, a.area_type, f.year;
