-- =============================================================================
-- 07_analytics.sql  |  Portable analytical queries (CTEs, window functions)
-- Each block starts with "-- @query <name>"; tests/crosscheck.py runs every block
-- and verifies selected results against an independent pandas computation.
-- Country-level questions always filter area_type = 'country_or_territory'.
-- =============================================================================

-- @query A01_global_access_trend
-- Global electricity access, total/urban/rural, with year-on-year change (LAG).
SELECT year, elec_access_pct, elec_access_urban_pct, elec_access_rural_pct,
       ROUND(CAST(elec_access_pct - LAG(elec_access_pct) OVER (ORDER BY year) AS NUMERIC), 2) AS yoy_pp
FROM mart.v_country_year
WHERE iso3 = 'WLD' AND elec_access_pct IS NOT NULL
ORDER BY year;

-- @query A02_top_access_gainers_2000_2022
-- Ten largest percentage-point gains in electricity access, 2000 -> 2022.
WITH pair AS (
    SELECT iso3, area_name,
           MAX(CASE WHEN year = 2000 THEN elec_access_pct END) AS v2000,
           MAX(CASE WHEN year = 2022 THEN elec_access_pct END) AS v2022
    FROM mart.v_country_year
    WHERE area_type = 'country_or_territory'
    GROUP BY iso3, area_name
), ranked AS (
    SELECT iso3, area_name, v2000, v2022, v2022 - v2000 AS gain_pp,
           ROW_NUMBER() OVER (ORDER BY v2022 - v2000 DESC, iso3) AS rnk
    FROM pair WHERE v2000 IS NOT NULL AND v2022 IS NOT NULL
)
SELECT rnk, iso3, area_name, v2000, v2022, ROUND(CAST(gain_pp AS NUMERIC), 1) AS gain_pp
FROM ranked WHERE rnk <= 10 ORDER BY rnk;

-- @query A03_access_bands_2022
-- Distribution of countries by electricity-access band (window over aggregate).
SELECT CASE WHEN elec_access_pct >= 99.5 THEN '1. Universal (>=99.5%)'
            WHEN elec_access_pct >= 90   THEN '2. High (90-99.5%)'
            WHEN elec_access_pct >= 50   THEN '3. Medium (50-90%)'
            ELSE                              '4. Low (<50%)' END AS band,
       COUNT(*) AS countries,
       ROUND(CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS NUMERIC), 1) AS pct_of_countries
FROM mart.v_country_year
WHERE year = 2022 AND area_type = 'country_or_territory' AND elec_access_pct IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- @query A04_urban_rural_gap_2022
-- Fifteen largest urban-minus-rural electricity access gaps.
SELECT iso3, area_name, elec_access_urban_pct AS urban, elec_access_rural_pct AS rural,
       ROUND(CAST(elec_access_urban_pct - elec_access_rural_pct AS NUMERIC), 1) AS gap_pp
FROM mart.v_country_year
WHERE year = 2022 AND area_type = 'country_or_territory'
  AND elec_access_urban_pct IS NOT NULL AND elec_access_rural_pct IS NOT NULL
ORDER BY elec_access_urban_pct - elec_access_rural_pct DESC, iso3
LIMIT 15;

-- @query A05_regional_scorecard_2022
-- World and regional aggregates side by side (aggregates are only compared with each other).
SELECT iso3, area_name, elec_access_pct, clean_cooking_pct, renewable_share_pct,
       renew_capacity_w_pc, energy_intensity_mj_per_gdp
FROM mart.v_country_year
WHERE year = 2022 AND area_type = 'aggregate'
ORDER BY elec_access_pct;

-- @query A06_renewable_share_change_1990_2021
-- Five largest rises and falls in the renewable share of final energy consumption.
WITH pair AS (
    SELECT iso3, area_name,
           MAX(CASE WHEN year = 1990 THEN renewable_share_pct END) AS v1990,
           MAX(CASE WHEN year = 2021 THEN renewable_share_pct END) AS v2021
    FROM mart.v_country_year WHERE area_type = 'country_or_territory'
    GROUP BY iso3, area_name
), d AS (
    SELECT iso3, area_name, v1990, v2021, v2021 - v1990 AS delta_pp FROM pair
    WHERE v1990 IS NOT NULL AND v2021 IS NOT NULL
), r AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY delta_pp DESC, iso3) AS up_rank,
              ROW_NUMBER() OVER (ORDER BY delta_pp ASC,  iso3) AS down_rank
    FROM d
)
SELECT 'increase' AS direction, up_rank AS rnk, iso3, area_name, v1990, v2021,
       ROUND(CAST(delta_pp AS NUMERIC), 1) AS delta_pp FROM r WHERE up_rank <= 5
UNION ALL
SELECT 'decrease', down_rank, iso3, area_name, v1990, v2021,
       ROUND(CAST(delta_pp AS NUMERIC), 1) FROM r WHERE down_rank <= 5
ORDER BY direction, rnk;

-- @query A07_renewable_capacity_mix_2022
-- Top-10 countries by installed renewable capacity per capita and their technology mix.
SELECT iso3, area_name, renew_capacity_w_pc,
       ROUND(CAST(100.0 * solar_capacity_w_pc / NULLIF(renew_capacity_w_pc, 0) AS NUMERIC), 1) AS solar_pct,
       ROUND(CAST(100.0 * wind_capacity_w_pc  / NULLIF(renew_capacity_w_pc, 0) AS NUMERIC), 1) AS wind_pct,
       ROUND(CAST(100.0 * hydro_capacity_w_pc / NULLIF(renew_capacity_w_pc, 0) AS NUMERIC), 1) AS hydro_pct
FROM mart.v_country_year
WHERE year = 2022 AND area_type = 'country_or_territory' AND renew_capacity_w_pc IS NOT NULL
ORDER BY renew_capacity_w_pc DESC, iso3
LIMIT 10;

-- @query A08_top_finance_recipients_2000_2022
-- Cumulative international financial commitments for renewables (millions of 2020 USD) by receiving
-- country, with share of the total across countries that report a value. Commitments, not payments.
WITH tot AS (
    SELECT iso3, area_name, SUM(intl_flows_usd_m) AS cum_usd_m
    FROM mart.v_country_year
    WHERE area_type = 'country_or_territory' AND year BETWEEN 2000 AND 2022
      AND intl_flows_usd_m IS NOT NULL
    GROUP BY iso3, area_name
), shared AS (
    SELECT iso3, area_name, cum_usd_m,
           100.0 * cum_usd_m / SUM(cum_usd_m) OVER () AS share_pct,
           ROW_NUMBER() OVER (ORDER BY cum_usd_m DESC, iso3) AS rnk
    FROM tot
)
SELECT rnk, iso3, area_name, ROUND(CAST(cum_usd_m AS NUMERIC), 0) AS cum_usd_m,
       ROUND(CAST(share_pct AS NUMERIC), 1) AS share_pct
FROM shared WHERE rnk <= 10 ORDER BY rnk;

-- @query A09_flows_by_source_and_decade
-- Financial commitments by technology and decade (millions of 2020 USD), with within-decade share.
WITH f AS (
    SELECT decade, breakdown_label, SUM(obs_value) AS usd_m
    FROM mart.v_observation
    WHERE indicator_code = 'WB_SE4ALL_EG_INFLW_IC' AND area_type = 'country_or_territory'
      AND breakdown_code <> 'WB_SE4ALL_RENEWSRC_ALLRENEW' AND obs_value IS NOT NULL
    GROUP BY decade, breakdown_label
)
SELECT decade, breakdown_label, ROUND(CAST(usd_m AS NUMERIC), 0) AS usd_m,
       ROUND(CAST(100.0 * usd_m / SUM(usd_m) OVER (PARTITION BY decade) AS NUMERIC), 1) AS pct_of_decade
FROM f ORDER BY decade, usd_m DESC;

-- @query A10_energy_intensity_best_improvers
-- Compound annual rate of change in energy intensity 2000 -> 2022 (more negative = better).
WITH pair AS (
    SELECT iso3, area_name,
           MAX(CASE WHEN year = 2000 THEN energy_intensity_mj_per_gdp END) AS v2000,
           MAX(CASE WHEN year = 2022 THEN energy_intensity_mj_per_gdp END) AS v2022
    FROM mart.v_country_year WHERE area_type = 'country_or_territory'
    GROUP BY iso3, area_name
), c AS (
    SELECT iso3, area_name, v2000, v2022,
           100.0 * (POWER(CAST(v2022 AS NUMERIC) / v2000, 1.0 / 22) - 1) AS cagr_pct,
           ROW_NUMBER() OVER (ORDER BY POWER(CAST(v2022 AS NUMERIC) / v2000, 1.0 / 22), iso3) AS rnk
    FROM pair WHERE v2000 > 0 AND v2022 > 0
)
SELECT rnk, iso3, area_name, v2000, v2022, ROUND(CAST(cagr_pct AS NUMERIC), 2) AS cagr_pct
FROM c WHERE rnk <= 10 ORDER BY rnk;

-- @query A11_data_coverage_by_indicator
-- Coverage profile per indicator: time span, observation count and publisher-flagged missing share.
SELECT i.indicator_code, i.sdg_indicator, MIN(f.year) AS first_year, MAX(f.year) AS last_year,
       COUNT(DISTINCT f.area_key) AS areas, COUNT(*) AS observations,
       SUM(CASE WHEN f.status_code = 'O' THEN 1 ELSE 0 END) AS missing_obs,
       ROUND(CAST(100.0 * SUM(CASE WHEN f.status_code = 'O' THEN 1 ELSE 0 END) / COUNT(*) AS NUMERIC), 1) AS missing_pct
FROM dw.fact_observation f
JOIN dw.dim_indicator i ON i.indicator_key = f.indicator_key
GROUP BY i.indicator_code, i.sdg_indicator
ORDER BY i.indicator_code;

-- @query A12_cooking_gap_2022
-- Countries that have nearly solved electrification but not clean cooking.
SELECT iso3, area_name, elec_access_pct, clean_cooking_pct,
       ROUND(CAST(elec_access_pct - clean_cooking_pct AS NUMERIC), 1) AS gap_pp
FROM mart.v_country_year
WHERE year = 2022 AND area_type = 'country_or_territory'
  AND elec_access_pct >= 90 AND clean_cooking_pct < 50
ORDER BY elec_access_pct - clean_cooking_pct DESC, iso3
LIMIT 15;
