-- =============================================================
-- PROJECT: Ireland Hospitality Sector SQL Analysis
-- FILE:    02_clean_data.sql
-- AUTHOR:  Cleiton Silva
-- SOURCE:  CSO Ireland Business Demography (BRA30, BRA34, BRA35)
-- DATE:    2025
-- =============================================================
-- DESCRIPTION:
--   Loads, validates, and cleans the raw CSO Ireland CSV data
--   into the schema created in 01_create_tables.sql.
--   Run AFTER 01_create_tables.sql.
--
-- DATA FILES EXPECTED in data/raw/:
--   - BRA34_activity_county.csv       (active enterprises by sector & county)
--   - BRA35_enterprise_deaths.csv     (closures by sector & size)
--   - BRA31_enterprise_births.csv     (new businesses by sector & size)
--   - failte_tourism_county.csv       (tourism arrivals by county)
-- =============================================================


SET search_path TO hospitality;


-- =============================================================
-- STEP 1: STAGING TABLES
-- Raw data lands here first — no constraints, all TEXT.
-- This lets us inspect and fix issues before loading into
-- the real tables.
-- =============================================================

DROP TABLE IF EXISTS staging_enterprise_activity;
CREATE TABLE staging_enterprise_activity (
    raw_year            TEXT,
    raw_county          TEXT,
    raw_sector          TEXT,
    raw_nace_code       TEXT,
    raw_size_class      TEXT,
    raw_active          TEXT,
    raw_persons         TEXT,
    source_file         TEXT DEFAULT 'BRA34_activity_county.csv'
);

DROP TABLE IF EXISTS staging_enterprise_deaths;
CREATE TABLE staging_enterprise_deaths (
    raw_year            TEXT,
    raw_county          TEXT,
    raw_sector          TEXT,
    raw_nace_code       TEXT,
    raw_size_class      TEXT,
    raw_ceased          TEXT,
    raw_persons         TEXT,
    source_file         TEXT DEFAULT 'BRA35_enterprise_deaths.csv'
);

DROP TABLE IF EXISTS staging_enterprise_births;
CREATE TABLE staging_enterprise_births (
    raw_year            TEXT,
    raw_county          TEXT,
    raw_sector          TEXT,
    raw_nace_code       TEXT,
    raw_size_class      TEXT,
    raw_new             TEXT,
    raw_persons         TEXT,
    source_file         TEXT DEFAULT 'BRA31_enterprise_births.csv'
);

DROP TABLE IF EXISTS staging_tourism;
CREATE TABLE staging_tourism (
    raw_year            TEXT,
    raw_county          TEXT,
    raw_region          TEXT,
    raw_overseas        TEXT,
    raw_domestic        TEXT,
    raw_revenue         TEXT,
    raw_avg_spend       TEXT,
    raw_occupancy       TEXT,
    source_file         TEXT DEFAULT 'failte_tourism_county.csv'
);


-- =============================================================
-- STEP 2: LOAD CSV FILES INTO STAGING
-- In VS Code with SQLTools: right-click the sql folder
-- and open a terminal, then run the \COPY commands below.
-- OR use pgAdmin 4: right-click table → Import/Export.
-- =============================================================

-- After downloading from CSO (data.cso.ie), run these in
-- psql terminal (adjust path to where you saved the files):

/*
\COPY staging_enterprise_activity (raw_year, raw_county, raw_sector, raw_nace_code, raw_size_class, raw_active, raw_persons)
FROM 'C:/Users/YourName/Projects/ireland-hospitality-sql-analysis/data/raw/BRA34_activity_county.csv'
DELIMITER ',' CSV HEADER ENCODING 'UTF8';

\COPY staging_enterprise_deaths (raw_year, raw_county, raw_sector, raw_nace_code, raw_size_class, raw_ceased, raw_persons)
FROM 'C:/Users/YourName/Projects/ireland-hospitality-sql-analysis/data/raw/BRA35_enterprise_deaths.csv'
DELIMITER ',' CSV HEADER ENCODING 'UTF8';

\COPY staging_enterprise_births (raw_year, raw_county, raw_sector, raw_nace_code, raw_size_class, raw_new, raw_persons)
FROM 'C:/Users/YourName/Projects/ireland-hospitality-sql-analysis/data/raw/BRA31_enterprise_births.csv'
DELIMITER ',' CSV HEADER ENCODING 'UTF8';

\COPY staging_tourism (raw_year, raw_county, raw_region, raw_overseas, raw_domestic, raw_revenue, raw_avg_spend, raw_occupancy)
FROM 'C:/Users/YourName/Projects/ireland-hospitality-sql-analysis/data/raw/failte_tourism_county.csv'
DELIMITER ',' CSV HEADER ENCODING 'UTF8';
*/


-- =============================================================
-- STEP 3: DATA QUALITY CHECKS ON STAGING
-- Always run these BEFORE loading into production tables.
-- Review the output carefully.
-- =============================================================

-- 3a. Check row counts (should be > 0 after loading CSVs)
SELECT 'staging_enterprise_activity' AS table_name, COUNT(*) AS row_count FROM staging_enterprise_activity
UNION ALL
SELECT 'staging_enterprise_deaths',                  COUNT(*) FROM staging_enterprise_deaths
UNION ALL
SELECT 'staging_enterprise_births',                  COUNT(*) FROM staging_enterprise_births
UNION ALL
SELECT 'staging_tourism',                             COUNT(*) FROM staging_tourism;

-- 3b. Check for NULL or empty values in critical columns
SELECT
    'activity' AS source,
    COUNT(*)   AS total_rows,
    COUNT(*) FILTER (WHERE raw_year    IS NULL OR raw_year    = '') AS null_year,
    COUNT(*) FILTER (WHERE raw_county  IS NULL OR raw_county  = '') AS null_county,
    COUNT(*) FILTER (WHERE raw_active  IS NULL OR raw_active  = '') AS null_active
FROM staging_enterprise_activity
UNION ALL
SELECT
    'deaths',
    COUNT(*),
    COUNT(*) FILTER (WHERE raw_year   IS NULL OR raw_year   = ''),
    COUNT(*) FILTER (WHERE raw_county IS NULL OR raw_county = ''),
    COUNT(*) FILTER (WHERE raw_ceased IS NULL OR raw_ceased = '')
FROM staging_enterprise_deaths;

-- 3c. Check year range (we expect 2019-2023)
SELECT
    raw_year,
    COUNT(*) AS records
FROM staging_enterprise_activity
GROUP BY raw_year
ORDER BY raw_year;

-- 3d. Check for county names that don't match our reference table
SELECT DISTINCT
    s.raw_county,
    c.county_name,
    CASE WHEN c.county_id IS NULL THEN 'NO MATCH - needs fix' ELSE 'OK' END AS status
FROM staging_enterprise_activity s
LEFT JOIN counties c
    ON TRIM(UPPER(s.raw_county)) = TRIM(UPPER(c.county_name))
ORDER BY status DESC, s.raw_county;

-- 3e. Check for NACE codes that don't match sectors table
SELECT DISTINCT
    s.raw_nace_code,
    sec.nace_code,
    CASE WHEN sec.sector_id IS NULL THEN 'NO MATCH - needs fix' ELSE 'OK' END AS status
FROM staging_enterprise_activity s
LEFT JOIN sectors sec
    ON TRIM(UPPER(s.raw_nace_code)) = TRIM(UPPER(sec.nace_code))
ORDER BY status DESC;

-- 3f. Check for non-numeric values in numeric columns
SELECT
    raw_active,
    raw_persons,
    COUNT(*) AS occurrences
FROM staging_enterprise_activity
WHERE raw_active  ~ '[^0-9]'   -- contains anything that is not a digit
   OR raw_persons ~ '[^0-9]'
GROUP BY raw_active, raw_persons
ORDER BY occurrences DESC;


-- =============================================================
-- STEP 4: CLEAN AND STANDARDISE
-- Fix issues found in Step 3 before loading into main tables.
-- =============================================================

-- 4a. Standardise county names (trim whitespace, fix capitalisation)
UPDATE staging_enterprise_activity  SET raw_county = INITCAP(TRIM(raw_county));
UPDATE staging_enterprise_deaths    SET raw_county = INITCAP(TRIM(raw_county));
UPDATE staging_enterprise_births    SET raw_county = INITCAP(TRIM(raw_county));
UPDATE staging_tourism              SET raw_county = INITCAP(TRIM(raw_county));

-- 4b. Standardise NACE codes (uppercase, trim)
UPDATE staging_enterprise_activity  SET raw_nace_code = UPPER(TRIM(raw_nace_code));
UPDATE staging_enterprise_deaths    SET raw_nace_code = UPPER(TRIM(raw_nace_code));
UPDATE staging_enterprise_births    SET raw_nace_code = UPPER(TRIM(raw_nace_code));

-- 4c. Replace CSO placeholder values with NULL
--     CSO uses '..' to indicate confidential/suppressed data
UPDATE staging_enterprise_activity
SET
    raw_active  = NULL WHERE raw_active  IN ('..', 'N/A', '-', '');
UPDATE staging_enterprise_activity
SET
    raw_persons = NULL WHERE raw_persons IN ('..', 'N/A', '-', '');

UPDATE staging_enterprise_deaths
SET
    raw_ceased  = NULL WHERE raw_ceased  IN ('..', 'N/A', '-', '');
UPDATE staging_enterprise_deaths
SET
    raw_persons = NULL WHERE raw_persons IN ('..', 'N/A', '-', '');

UPDATE staging_enterprise_births
SET
    raw_new     = NULL WHERE raw_new     IN ('..', 'N/A', '-', '');

-- 4d. Standardise size class labels to match our reference table
UPDATE staging_enterprise_activity
SET raw_size_class = CASE
    WHEN raw_size_class ILIKE '%0-9%'     OR raw_size_class ILIKE 'micro%'  THEN 'micro'
    WHEN raw_size_class ILIKE '%10-49%'   OR raw_size_class ILIKE 'small%'  THEN 'small'
    WHEN raw_size_class ILIKE '%50-249%'  OR raw_size_class ILIKE 'medium%' THEN 'medium'
    WHEN raw_size_class ILIKE '%250%'     OR raw_size_class ILIKE 'large%'  THEN 'large'
    ELSE raw_size_class
END;

UPDATE staging_enterprise_deaths
SET raw_size_class = CASE
    WHEN raw_size_class ILIKE '%0-9%'     OR raw_size_class ILIKE 'micro%'  THEN 'micro'
    WHEN raw_size_class ILIKE '%10-49%'   OR raw_size_class ILIKE 'small%'  THEN 'small'
    WHEN raw_size_class ILIKE '%50-249%'  OR raw_size_class ILIKE 'medium%' THEN 'medium'
    WHEN raw_size_class ILIKE '%250%'     OR raw_size_class ILIKE 'large%'  THEN 'large'
    ELSE raw_size_class
END;


-- =============================================================
-- STEP 5: LOAD INTO PRODUCTION TABLES
-- Only rows that pass all joins (county, sector, size all
-- match reference tables) are loaded. Bad rows are skipped.
-- =============================================================

-- 5a. Load enterprise_activity
INSERT INTO enterprise_activity
    (year, county_id, sector_id, size_id, active_enterprises, persons_employed)
SELECT
    raw_year::SMALLINT,
    c.county_id,
    s.sector_id,
    sc.size_id,
    COALESCE(raw_active::INT,  0),
    COALESCE(raw_persons::INT, 0)
FROM staging_enterprise_activity sta
JOIN counties                 c  ON UPPER(TRIM(sta.raw_county))     = UPPER(c.county_name)
JOIN sectors                  s  ON UPPER(TRIM(sta.raw_nace_code))  = UPPER(s.nace_code)
JOIN enterprise_size_classes  sc ON LOWER(TRIM(sta.raw_size_class)) = sc.size_code
ON CONFLICT (year, county_id, sector_id, size_id) DO UPDATE SET
    active_enterprises = EXCLUDED.active_enterprises,
    persons_employed   = EXCLUDED.persons_employed;

-- 5b. Load enterprise_deaths
INSERT INTO enterprise_deaths
    (year, county_id, sector_id, size_id, ceased_enterprises, persons_employed)
SELECT
    raw_year::SMALLINT,
    c.county_id,
    s.sector_id,
    sc.size_id,
    COALESCE(raw_ceased::INT,  0),
    COALESCE(raw_persons::INT, 0)
FROM staging_enterprise_deaths std
JOIN counties                 c  ON UPPER(TRIM(std.raw_county))     = UPPER(c.county_name)
JOIN sectors                  s  ON UPPER(TRIM(std.raw_nace_code))  = UPPER(s.nace_code)
JOIN enterprise_size_classes  sc ON LOWER(TRIM(std.raw_size_class)) = sc.size_code
ON CONFLICT (year, county_id, sector_id, size_id) DO UPDATE SET
    ceased_enterprises = EXCLUDED.ceased_enterprises,
    persons_employed   = EXCLUDED.persons_employed;

-- 5c. Load enterprise_births
INSERT INTO enterprise_births
    (year, county_id, sector_id, size_id, new_enterprises, persons_employed)
SELECT
    raw_year::SMALLINT,
    c.county_id,
    s.sector_id,
    sc.size_id,
    COALESCE(raw_new::INT,     0),
    COALESCE(raw_persons::INT, 0)
FROM staging_enterprise_births stb
JOIN counties                 c  ON UPPER(TRIM(stb.raw_county))     = UPPER(c.county_name)
JOIN sectors                  s  ON UPPER(TRIM(stb.raw_nace_code))  = UPPER(s.nace_code)
JOIN enterprise_size_classes  sc ON LOWER(TRIM(stb.raw_size_class)) = sc.size_code
ON CONFLICT (year, county_id, sector_id, size_id) DO UPDATE SET
    new_enterprises  = EXCLUDED.new_enterprises,
    persons_employed = EXCLUDED.persons_employed;

-- 5d. Load tourism_arrivals
INSERT INTO tourism_arrivals
    (year, county_id, region_name, overseas_visitors, domestic_visitors,
     total_revenue_eur_m, avg_spend_per_visitor, hotel_occupancy_pct)
SELECT
    raw_year::SMALLINT,
    c.county_id,
    TRIM(raw_region),
    NULLIF(REPLACE(raw_overseas, ',', ''), '')::INT,
    NULLIF(REPLACE(raw_domestic, ',', ''), '')::INT,
    NULLIF(REPLACE(raw_revenue,  ',', ''), '')::NUMERIC,
    NULLIF(raw_avg_spend,  '')::NUMERIC,
    NULLIF(raw_occupancy,  '')::NUMERIC
FROM staging_tourism st
JOIN counties c ON UPPER(TRIM(st.raw_county)) = UPPER(c.county_name)
ON CONFLICT (year, county_id) DO UPDATE SET
    overseas_visitors     = EXCLUDED.overseas_visitors,
    domestic_visitors     = EXCLUDED.domestic_visitors,
    total_revenue_eur_m   = EXCLUDED.total_revenue_eur_m,
    avg_spend_per_visitor = EXCLUDED.avg_spend_per_visitor,
    hotel_occupancy_pct   = EXCLUDED.hotel_occupancy_pct;


-- =============================================================
-- STEP 6: FINAL VALIDATION
-- Confirm data loaded correctly into production tables.
-- =============================================================

-- 6a. Row counts per table
SELECT 'enterprise_activity' AS tbl, COUNT(*) AS rows FROM enterprise_activity
UNION ALL
SELECT 'enterprise_deaths',          COUNT(*) FROM enterprise_deaths
UNION ALL
SELECT 'enterprise_births',          COUNT(*) FROM enterprise_births
UNION ALL
SELECT 'tourism_arrivals',           COUNT(*) FROM tourism_arrivals
UNION ALL
SELECT 'hospitality_revenue',        COUNT(*) FROM hospitality_revenue
UNION ALL
SELECT 'operational_cost_index',     COUNT(*) FROM operational_cost_index;

-- 6b. Spot check: total active hospitality enterprises per year
SELECT
    ea.year,
    SUM(ea.active_enterprises)  AS total_active,
    SUM(ea.persons_employed)    AS total_employed
FROM enterprise_activity ea
JOIN sectors s ON ea.sector_id = s.sector_id
WHERE s.is_hospitality = TRUE
GROUP BY ea.year
ORDER BY ea.year;

-- 6c. Spot check: total closures per year (hospitality only)
SELECT
    ed.year,
    SUM(ed.ceased_enterprises)  AS total_closures,
    SUM(ed.persons_employed)    AS jobs_lost
FROM enterprise_deaths ed
JOIN sectors s ON ed.sector_id = s.sector_id
WHERE s.is_hospitality = TRUE
GROUP BY ed.year
ORDER BY ed.year;

-- 6d. Rows skipped (staging rows that didn't join to reference tables)
SELECT
    'activity skipped' AS check_name,
    COUNT(*) AS skipped_rows
FROM staging_enterprise_activity sta
WHERE NOT EXISTS (
    SELECT 1 FROM counties c
    WHERE UPPER(TRIM(sta.raw_county)) = UPPER(c.county_name)
)
UNION ALL
SELECT
    'deaths skipped',
    COUNT(*)
FROM staging_enterprise_deaths std
WHERE NOT EXISTS (
    SELECT 1 FROM counties c
    WHERE UPPER(TRIM(std.raw_county)) = UPPER(c.county_name)
);
