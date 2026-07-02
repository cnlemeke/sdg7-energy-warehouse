-- =============================================================================
-- 08_postgres_advanced.sql  |  PostgreSQL-specific analytics
-- (statistical aggregates, ordered-set aggregates, ROLLUP, DISTINCT ON, generate_series)
-- =============================================================================

-- B01 Pearson correlation between electricity access and clean-cooking access, by year.
SELECT year,
       COUNT(*)                                                    AS n_countries,
       ROUND(CORR(elec_access_pct, clean_cooking_pct)::numeric, 3) AS pearson_r
FROM mart.v_country_year
WHERE area_type = 'country_or_territory'
  AND elec_access_pct IS NOT NULL AND clean_cooking_pct IS NOT NULL
GROUP BY year ORDER BY year;

-- B02 Linear-trend projection: year each country reaches 100% electricity access
--     at its own 2012-2022 pace (OLS via regr_slope / regr_intercept).
WITH fit AS (
    SELECT iso3, area_name,
           regr_slope(elec_access_pct, year)     AS slope_pp_per_year,
           regr_intercept(elec_access_pct, year) AS intercept,
           MAX(elec_access_pct) FILTER (WHERE year = 2022) AS access_2022,
           COUNT(elec_access_pct) AS n_obs
    FROM mart.v_country_year
    WHERE area_type = 'country_or_territory' AND year BETWEEN 2012 AND 2022
      AND elec_access_pct IS NOT NULL
    GROUP BY iso3, area_name
)
SELECT iso3, area_name, access_2022,
       ROUND(slope_pp_per_year::numeric, 2) AS pp_per_year,
       CEIL((100 - intercept) / slope_pp_per_year)::int AS projected_year_100pct
FROM fit
WHERE n_obs >= 8 AND access_2022 < 99.5 AND slope_pp_per_year > 0
ORDER BY projected_year_100pct DESC
LIMIT 20;

-- B03 Distribution of national access by year: quartiles via ordered-set aggregates.
SELECT year,
       percentile_cont(0.25) WITHIN GROUP (ORDER BY elec_access_pct) AS q1,
       percentile_cont(0.50) WITHIN GROUP (ORDER BY elec_access_pct) AS median,
       percentile_cont(0.75) WITHIN GROUP (ORDER BY elec_access_pct) AS q3
FROM mart.v_country_year
WHERE area_type = 'country_or_territory' AND elec_access_pct IS NOT NULL
GROUP BY year ORDER BY year;

-- B04 ROLLUP: financial flows by decade and technology with sub-totals and grand total.
SELECT COALESCE(decade::text, 'ALL')          AS decade,
       COALESCE(breakdown_label, 'ALL SOURCES') AS source,
       ROUND(SUM(obs_value), 0)               AS usd_m
FROM mart.v_observation
WHERE indicator_code = 'WB_SE4ALL_EG_INFLW_IC' AND area_type = 'country_or_territory'
  AND breakdown_code <> 'WB_SE4ALL_RENEWSRC_ALLRENEW'
GROUP BY ROLLUP (decade, breakdown_label)
ORDER BY decade NULLS LAST, breakdown_label NULLS LAST;

-- B05 DISTINCT ON: most recent non-missing electricity-access value per country.
SELECT DISTINCT ON (iso3) iso3, area_name, year AS latest_year, elec_access_pct
FROM mart.v_country_year
WHERE area_type = 'country_or_territory' AND elec_access_pct IS NOT NULL
ORDER BY iso3, year DESC;

-- B06 Gap detection with generate_series: countries with missing years inside their access series.
WITH span AS (
    SELECT iso3, MIN(year) AS y0, MAX(year) AS y1
    FROM mart.v_country_year WHERE elec_access_pct IS NOT NULL GROUP BY iso3
)
SELECT s.iso3, array_agg(g.y ORDER BY g.y) AS missing_years
FROM span s
CROSS JOIN LATERAL generate_series(s.y0::int, s.y1::int) AS g(y)
WHERE NOT EXISTS (SELECT 1 FROM mart.v_country_year v
                  WHERE v.iso3 = s.iso3 AND v.year = g.y AND v.elec_access_pct IS NOT NULL)
GROUP BY s.iso3 ORDER BY s.iso3;
