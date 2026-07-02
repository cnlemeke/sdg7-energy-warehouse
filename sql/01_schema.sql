-- =============================================================================
-- 01_schema.sql  |  Schemas, staging table, star-schema warehouse (PostgreSQL 14+)
-- Layers:  staging (raw, untyped)  ->  dw (typed, conformed star schema)
--          ->  mart (analyst-facing views)   |  dq (quality rules)  |  audit
-- Idempotent: safe to re-run.
-- =============================================================================
\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS dw;
CREATE SCHEMA IF NOT EXISTS mart;
CREATE SCHEMA IF NOT EXISTS dq;
CREATE SCHEMA IF NOT EXISTS audit;

-- ---------------------------------------------------------------------------
-- STAGING: 1:1 image of the Data360 SDMX export. Everything is TEXT so the load
-- can never fail on a type problem; typing happens (and is validated) in 03.
-- Column ORDER must match the CSV because \copy ignores header names.
-- ---------------------------------------------------------------------------
-- CASCADE also drops dq.check_results, which reads this table. Script 05 recreates it.
DROP TABLE IF EXISTS staging.se4all_raw CASCADE;
CREATE TABLE staging.se4all_raw (
    structure                text,
    structure_id             text,
    action                   text,
    freq                     text,
    freq_label               text,
    ref_area                 text,
    ref_area_label           text,
    indicator                text,
    indicator_label          text,
    sex                      text,
    sex_label                text,
    age                      text,
    age_label                text,
    urbanisation             text,
    urbanisation_label       text,
    unit_measure             text,
    unit_measure_label       text,
    comp_breakdown_1         text,
    comp_breakdown_1_label   text,
    comp_breakdown_2         text,
    comp_breakdown_2_label   text,
    comp_breakdown_3         text,
    comp_breakdown_3_label   text,
    time_period              text,
    obs_value                text,
    agg_method               text,
    agg_method_label         text,
    database_id              text,
    database_id_label        text,
    unit_mult                text,
    unit_mult_label          text,
    unit_type                text,
    unit_type_label          text,
    time_format              text,
    time_format_label        text,
    obs_status               text,
    obs_status_label         text,
    obs_conf                 text,
    obs_conf_label           text
);
COMMENT ON TABLE staging.se4all_raw IS
  'Verbatim World Bank Data360 WB_SE4ALL export (SDMX long format). Not for analyst use.';

-- ---------------------------------------------------------------------------
-- DIMENSIONS
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS dw.fact_observation CASCADE;
DROP TABLE IF EXISTS dw.dim_area, dw.dim_indicator, dw.dim_breakdown,
                     dw.dim_urbanisation, dw.dim_year, dw.dim_obs_status CASCADE;

CREATE TABLE dw.dim_area (
    area_key   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    iso3       char(3) NOT NULL UNIQUE,
    area_name  text    NOT NULL,
    area_type  text    NOT NULL CHECK (area_type IN ('country_or_territory', 'aggregate'))
);
COMMENT ON COLUMN dw.dim_area.area_type IS
  'aggregate = World / regional totals. Never sum these together with countries.';

CREATE TABLE dw.dim_indicator (
    indicator_key   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    indicator_code  text NOT NULL UNIQUE,
    indicator_name  text NOT NULL,
    unit_code       text NOT NULL,
    unit_name       text NOT NULL,
    unit_type       text NOT NULL,
    unit_multiplier integer NOT NULL,   -- as published; see docs/DATA_DICTIONARY.md (W_PER_C anomaly)
    agg_method      text NOT NULL,      -- how the source aggregates to regions: W_AVG | SUM
    theme           text NOT NULL,
    sdg_indicator   text                -- UN SDG 7 indicator reference; NULL for supporting series
);

CREATE TABLE dw.dim_breakdown (
    breakdown_key    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    breakdown_code   text NOT NULL UNIQUE,
    breakdown_label  text NOT NULL,
    breakdown_family text NOT NULL CHECK (breakdown_family IN ('NONE','RENEWABLE_SOURCE','ENERGY_USE_TYPE'))
);

CREATE TABLE dw.dim_urbanisation (
    urb_key   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    urb_code  text NOT NULL UNIQUE,      -- _T total | URB urban | RUR rural
    urb_label text NOT NULL
);

CREATE TABLE dw.dim_year (
    year   smallint PRIMARY KEY,
    decade smallint NOT NULL
);

CREATE TABLE dw.dim_obs_status (
    status_code  char(1) PRIMARY KEY,    -- A normal | O missing
    status_label text NOT NULL
);

-- ---------------------------------------------------------------------------
-- FACT: one row per (indicator, area, breakdown, urbanisation, year).
-- RANGE-partitioned by year (decades) so time-bounded queries prune partitions.
-- The primary key is the grain; a CHECK ties NULL values to the 'O' status.
-- ---------------------------------------------------------------------------
CREATE TABLE dw.fact_observation (
    area_key      integer  NOT NULL REFERENCES dw.dim_area(area_key),
    indicator_key integer  NOT NULL REFERENCES dw.dim_indicator(indicator_key),
    breakdown_key integer  NOT NULL REFERENCES dw.dim_breakdown(breakdown_key),
    urb_key       integer  NOT NULL REFERENCES dw.dim_urbanisation(urb_key),
    year          smallint NOT NULL REFERENCES dw.dim_year(year),
    obs_value     numeric(20,8),  -- source shows up to 6 real decimals plus float noise; 4 decimals would round real data
    status_code   char(1)  NOT NULL REFERENCES dw.dim_obs_status(status_code),
    CONSTRAINT pk_fact_observation
        PRIMARY KEY (indicator_key, area_key, breakdown_key, urb_key, year),
    CONSTRAINT ck_value_matches_status
        CHECK ((obs_value IS NULL) = (status_code = 'O'))
) PARTITION BY RANGE (year);

CREATE TABLE dw.fact_observation_1990s PARTITION OF dw.fact_observation FOR VALUES FROM (1990) TO (2000);
CREATE TABLE dw.fact_observation_2000s PARTITION OF dw.fact_observation FOR VALUES FROM (2000) TO (2010);
CREATE TABLE dw.fact_observation_2010s PARTITION OF dw.fact_observation FOR VALUES FROM (2010) TO (2020);
CREATE TABLE dw.fact_observation_2020s PARTITION OF dw.fact_observation FOR VALUES FROM (2020) TO (2030);

-- ---------------------------------------------------------------------------
-- AUDIT: lightweight ETL run log
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit.etl_run_log (
    run_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    step      text        NOT NULL,
    rows_in   bigint,
    rows_out  bigint,
    logged_at timestamptz NOT NULL DEFAULT now()
);
