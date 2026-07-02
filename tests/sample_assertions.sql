-- =============================================================================
-- sample_assertions.sql  |  Checks that only hold for the committed 13-area sample.
-- Run after the pipeline:  psql -v ON_ERROR_STOP=1 -f tests/sample_assertions.sql
-- Each check raises an error when it fails. (A CASE ... ELSE 1/0 trick does not work
-- here, because PostgreSQL evaluates the constant 1/0 while planning the query.)
-- =============================================================================
DO $$
BEGIN
    IF (SELECT count(*) FROM dw.fact_observation) <> 7801 THEN
        RAISE EXCEPTION 'expected 7801 fact rows, found %', (SELECT count(*) FROM dw.fact_observation);
    END IF;
    IF (SELECT area_name FROM dw.dim_area WHERE iso3 = 'BLM') IS DISTINCT FROM 'Saint-Barthélemy (Fr.)' THEN
        RAISE EXCEPTION 'mojibake in the BLM area name was not repaired';
    END IF;
    IF (SELECT count(*) FROM dw.dim_area) <> 13 THEN
        RAISE EXCEPTION 'expected 13 areas';
    END IF;
    RAISE NOTICE 'sample assertions passed';
END $$;
