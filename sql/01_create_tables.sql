-- =============================================================
-- PROJECT: Ireland Hospitality Sector SQL Analysis
-- FILE:    01_create_tables.sql  (v2 - based on real CSO data)
-- AUTHOR:  Cleiton Silva
-- SOURCE:  CSO Ireland BRA34 - Business Demography by Activity and County
-- DATE:    2025
-- =============================================================
-- REAL DATA FORMAT (from BRA34 CSV):
--   Columns: Statistic Label | Year | Activity | County | UNIT | VALUE
--   Statistic Label: "Active Enterprise", "Persons Engaged", "Employees"
--   Years: 2019, 2020, 2021, 2022, 2023
--   Counties: 26 Irish counties (format: "Co. Dublin", "Co. Cork", etc.)
-- =============================================================

-- Create schema
CREATE SCHEMA IF NOT EXISTS hospitality;
SET search_path TO hospitality;

-- Drop tables if re-running (clean slate)
DROP TABLE IF EXISTS enterprise_data CASCADE;
DROP TABLE IF EXISTS county_summary CASCADE;
DROP TABLE IF EXISTS sector_comparison CASCADE;

-- =============================================================
-- TABLE 1: enterprise_data
-- Main fact table — mirrors the real CSO CSV structure exactly
-- =============================================================

CREATE TABLE IF NOT EXISTS enterprise_data (
    id               SERIAL       PRIMARY KEY,
    statistic        VARCHAR(50)  NOT NULL,  -- 'Active Enterprise', 'Persons Engaged', 'Employees'
    year             SMALLINT     NOT NULL,
    activity         VARCHAR(150) NOT NULL,  -- full activity name as in CSV
    county           VARCHAR(50)  NOT NULL,  -- 'Co. Dublin', 'Co. Cork', etc.
    value            NUMERIC(10,1),          -- NULL means suppressed by CSO
    -- derived helper columns (filled after INSERT)
    is_hospitality   BOOLEAN      DEFAULT FALSE,
    sector_group     VARCHAR(20)  DEFAULT 'other'  -- 'total', 'accommodation', 'food_beverage'
);

-- =============================================================
-- TABLE 2: hospitality_county_year
-- Clean analytical table: one row per county per year
-- with all 3 metrics as columns — easier to query
-- =============================================================

CREATE TABLE IF NOT EXISTS hospitality_county_year (
    id                   SERIAL      PRIMARY KEY,
    year                 SMALLINT    NOT NULL,
    county               VARCHAR(50) NOT NULL,
    activity             VARCHAR(150) NOT NULL,
    active_enterprises   NUMERIC(10,1),
    persons_engaged      NUMERIC(10,1),
    employees            NUMERIC(10,1),
    UNIQUE (year, county, activity)
);

-- =============================================================
-- LOAD DATA: import from CSO CSV
-- Run this block in psql terminal:
--
--   \i sql/01_create_tables.sql
--
-- Then load the CSV (adjust path to your actual file location):
--
-- \COPY hospitality.enterprise_data
--   (statistic, year, activity, county, value)
-- FROM 'C:/Users/cleit/Projects/ireland-hospitality-sql-analysis/data/raw/BRA34_20260416T220421.csv'
-- DELIMITER ',' CSV HEADER ENCODING 'UTF8';
--
-- =============================================================

-- =============================================================
-- STEP 2: Mark hospitality rows
-- =============================================================

UPDATE enterprise_data
SET
    is_hospitality = TRUE,
    sector_group   = CASE
        WHEN activity ILIKE '%Accommodation and Food Service%' THEN 'total'
        WHEN activity ILIKE '%Accommodation (I55)%'            THEN 'accommodation'
        WHEN activity ILIKE '%Food and Beverage%'              THEN 'food_beverage'
        ELSE 'other'
    END
WHERE activity ILIKE '%Accommodation%'
   OR activity ILIKE '%Food and Beverage%';

-- =============================================================
-- STEP 3: Build clean analytical table
-- Pivot the 3 statistics into columns
-- =============================================================

INSERT INTO hospitality_county_year
    (year, county, activity, active_enterprises, persons_engaged, employees)
SELECT
    year,
    county,
    activity,
    MAX(value) FILTER (WHERE statistic = 'Active Enterprise') AS active_enterprises,
    MAX(value) FILTER (WHERE statistic = 'Persons Engaged')   AS persons_engaged,
    MAX(value) FILTER (WHERE statistic = 'Employees')         AS employees
FROM enterprise_data
WHERE is_hospitality = TRUE
  AND county != 'Ireland'          -- exclude national totals
  AND county != 'Unknown county'
GROUP BY year, county, activity
ON CONFLICT (year, county, activity) DO UPDATE SET
    active_enterprises = EXCLUDED.active_enterprises,
    persons_engaged    = EXCLUDED.persons_engaged,
    employees          = EXCLUDED.employees;

-- =============================================================
-- VERIFY: check tables loaded correctly
-- =============================================================

SELECT 'enterprise_data rows'          AS check_name, COUNT(*) AS result FROM enterprise_data
UNION ALL
SELECT 'hospitality rows',              COUNT(*) FROM enterprise_data WHERE is_hospitality = TRUE
UNION ALL
SELECT 'hospitality_county_year rows',  COUNT(*) FROM hospitality_county_year;

-- Quick preview of clean data
SELECT * FROM hospitality_county_year
WHERE activity ILIKE '%Accommodation and Food%'
ORDER BY year, county
LIMIT 10;
