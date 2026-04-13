-- =============================================================
-- PROJECT: Ireland Hospitality Sector SQL Analysis
-- FILE:    01_create_tables.sql
-- AUTHOR:  Cleiton Silva
-- SOURCE:  CSO Ireland Business Demography + Failte Ireland
-- DATE:    2026
-- =============================================================
-- DESCRIPTION:
--   Creates the full database schema for analysing Ireland's
--   hospitality sector: enterprise activity, closures, tourism,
--   and economic costs (2019-2023).
-- =============================================================


-- -------------------------------------------------------------
-- SETUP: create schema to keep project tables organised
-- -------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS hospitality;

SET search_path TO hospitality;


-- -------------------------------------------------------------
-- TABLE 1: sectors
-- Reference table for NACE Rev.2 economic activity codes
-- used by CSO Ireland in all Business Demography datasets.
-- -------------------------------------------------------------

CREATE TABLE IF NOT EXISTS sectors (
    sector_id       SERIAL          PRIMARY KEY,
    nace_code       VARCHAR(10)     NOT NULL UNIQUE,
    sector_name     VARCHAR(150)    NOT NULL,
    sector_group    VARCHAR(50)     NOT NULL,  -- 'hospitality', 'other_services', etc.
    is_hospitality  BOOLEAN         DEFAULT FALSE
);

-- Seed the sectors we care about
INSERT INTO sectors (nace_code, sector_name, sector_group, is_hospitality) VALUES
    ('I',    'Accommodation & Food Service Activities',       'hospitality',     TRUE),
    ('I551', 'Hotels & Similar Accommodation',               'hospitality',     TRUE),
    ('I552', 'Holiday & Short-Stay Accommodation',           'hospitality',     TRUE),
    ('I553', 'Camping Grounds & Recreational Vehicle Parks', 'hospitality',     TRUE),
    ('I559', 'Other Accommodation',                          'hospitality',     TRUE),
    ('I561', 'Restaurants & Mobile Food Service Activities', 'hospitality',     TRUE),
    ('I562', 'Event Catering & Other Food Service',          'hospitality',     TRUE),
    ('I563', 'Beverage Serving Activities',                  'hospitality',     TRUE),
    ('R',    'Arts, Entertainment & Recreation',             'other_services',  FALSE),
    ('G',    'Wholesale & Retail Trade',                     'distribution',    FALSE),
    ('F',    'Construction',                                 'construction',    FALSE)
ON CONFLICT (nace_code) DO NOTHING;


-- -------------------------------------------------------------
-- TABLE 2: counties
-- Reference table for Ireland's 26 counties.
-- -------------------------------------------------------------

CREATE TABLE IF NOT EXISTS counties (
    county_id   SERIAL          PRIMARY KEY,
    county_name VARCHAR(50)     NOT NULL UNIQUE,
    province    VARCHAR(20)     NOT NULL,  -- Leinster, Munster, Connacht, Ulster
    is_border   BOOLEAN         DEFAULT FALSE
);

INSERT INTO counties (county_name, province, is_border) VALUES
    -- Leinster
    ('Dublin',      'Leinster', FALSE),
    ('Wicklow',     'Leinster', FALSE),
    ('Wexford',     'Leinster', FALSE),
    ('Carlow',      'Leinster', FALSE),
    ('Kilkenny',    'Leinster', FALSE),
    ('Waterford',   'Leinster', FALSE),
    ('Tipperary',   'Leinster', FALSE),
    ('Laois',       'Leinster', FALSE),
    ('Offaly',      'Leinster', FALSE),
    ('Kildare',     'Leinster', FALSE),
    ('Meath',       'Leinster', FALSE),
    ('Louth',       'Leinster', TRUE),
    ('Longford',    'Leinster', FALSE),
    ('Westmeath',   'Leinster', FALSE),
    -- Munster
    ('Cork',        'Munster',  FALSE),
    ('Kerry',       'Munster',  FALSE),
    ('Limerick',    'Munster',  FALSE),
    ('Clare',       'Munster',  FALSE),
    -- Connacht
    ('Galway',      'Connacht', FALSE),
    ('Mayo',        'Connacht', FALSE),
    ('Roscommon',   'Connacht', FALSE),
    ('Sligo',       'Connacht', FALSE),
    ('Leitrim',     'Connacht', FALSE),
    -- Ulster (Republic)
    ('Donegal',     'Ulster',   TRUE),
    ('Cavan',       'Ulster',   TRUE),
    ('Monaghan',    'Ulster',   TRUE)
ON CONFLICT (county_name) DO NOTHING;


-- -------------------------------------------------------------
-- TABLE 3: enterprise_size_classes
-- Reference table for CSO employment size categories.
-- -------------------------------------------------------------

CREATE TABLE IF NOT EXISTS enterprise_size_classes (
    size_id         SERIAL          PRIMARY KEY,
    size_code       VARCHAR(10)     NOT NULL UNIQUE,
    size_label      VARCHAR(50)     NOT NULL,
    min_employees   INT             NOT NULL,
    max_employees   INT             -- NULL means no upper limit
);

INSERT INTO enterprise_size_classes (size_code, size_label, min_employees, max_employees) VALUES
    ('micro',   'Micro (0-9)',       0,   9),
    ('small',   'Small (10-49)',     10,  49),
    ('medium',  'Medium (50-249)',   50,  249),
    ('large',   'Large (250+)',      250, NULL)
ON CONFLICT (size_code) DO NOTHING;


-- -------------------------------------------------------------
-- TABLE 4: enterprise_activity
-- Main fact table: number of active enterprises per sector,
-- county, size class, and year.
-- Source: CSO BRA30 / BRA34
-- -------------------------------------------------------------

CREATE TABLE IF NOT EXISTS enterprise_activity (
    activity_id         SERIAL          PRIMARY KEY,
    year                SMALLINT        NOT NULL CHECK (year BETWEEN 2019 AND 2025),
    county_id           INT             REFERENCES counties(county_id),
    sector_id           INT             REFERENCES sectors(sector_id),
    size_id             INT             REFERENCES enterprise_size_classes(size_id),
    active_enterprises  INT             NOT NULL DEFAULT 0,
    persons_employed    INT             NOT NULL DEFAULT 0,
    created_at          TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (year, county_id, sector_id, size_id)
);


-- -------------------------------------------------------------
-- TABLE 5: enterprise_births
-- Newly active enterprises per year (CSO: BRA31)
-- -------------------------------------------------------------

CREATE TABLE IF NOT EXISTS enterprise_births (
    birth_id            SERIAL          PRIMARY KEY,
    year                SMALLINT        NOT NULL CHECK (year BETWEEN 2019 AND 2025),
    county_id           INT             REFERENCES counties(county_id),
    sector_id           INT             REFERENCES sectors(sector_id),
    size_id             INT             REFERENCES enterprise_size_classes(size_id),
    new_enterprises     INT             NOT NULL DEFAULT 0,
    persons_employed    INT             NOT NULL DEFAULT 0,
    created_at          TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (year, county_id, sector_id, size_id)
);


-- -------------------------------------------------------------
-- TABLE 6: enterprise_deaths
-- Enterprises that ceased activity per year (CSO: BRA35)
-- NOTE: CSO reports deaths with a 1-year lag
--       (2022 deaths appear in the 2023 report)
-- -------------------------------------------------------------

CREATE TABLE IF NOT EXISTS enterprise_deaths (
    death_id            SERIAL          PRIMARY KEY,
    year                SMALLINT        NOT NULL CHECK (year BETWEEN 2019 AND 2025),
    county_id           INT             REFERENCES counties(county_id),
    sector_id           INT             REFERENCES sectors(sector_id),
    size_id             INT             REFERENCES enterprise_size_classes(size_id),
    ceased_enterprises  INT             NOT NULL DEFAULT 0,
    persons_employed    INT             NOT NULL DEFAULT 0,
    created_at          TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (year, county_id, sector_id, size_id)
);


-- -------------------------------------------------------------
-- TABLE 7: hospitality_revenue
-- Annual GVA, revenue, and cost data by hospitality sub-sector.
-- Source: CSO Hospitality Value Chain Analysis
-- -------------------------------------------------------------

CREATE TABLE IF NOT EXISTS hospitality_revenue (
    revenue_id          SERIAL          PRIMARY KEY,
    year                SMALLINT        NOT NULL CHECK (year BETWEEN 2019 AND 2025),
    sector_id           INT             REFERENCES sectors(sector_id),
    total_sales_eur_m   NUMERIC(10,2),  -- total sales in millions EUR
    total_costs_eur_m   NUMERIC(10,2),  -- total costs in millions EUR
    gva_eur_m           NUMERIC(10,2),  -- Gross Value Added in millions EUR
    labour_costs_eur_m  NUMERIC(10,2),  -- labour/personnel costs in millions EUR
    energy_costs_eur_m  NUMERIC(10,2),  -- energy costs in millions EUR
    created_at          TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (year, sector_id)
);


-- -------------------------------------------------------------
-- TABLE 8: tourism_arrivals
-- Overseas and domestic visitor data by region.
-- Source: Failte Ireland Key Tourism Facts + CSO
-- -------------------------------------------------------------

CREATE TABLE IF NOT EXISTS tourism_arrivals (
    tourism_id              SERIAL          PRIMARY KEY,
    year                    SMALLINT        NOT NULL CHECK (year BETWEEN 2019 AND 2025),
    county_id               INT             REFERENCES counties(county_id),
    region_name             VARCHAR(80),    -- Wild Atlantic Way, Dublin, etc.
    overseas_visitors       INT,            -- total overseas visitors
    domestic_visitors       INT,            -- domestic overnight visitors
    total_revenue_eur_m     NUMERIC(10,2),  -- total tourism revenue in millions EUR
    avg_spend_per_visitor   NUMERIC(8,2),   -- average spend per overseas visitor
    hotel_occupancy_pct     NUMERIC(5,2),   -- hotel occupancy rate (%)
    created_at              TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (year, county_id)
);


-- -------------------------------------------------------------
-- TABLE 9: operational_cost_index
-- Tracks key cost pressures affecting hospitality businesses:
-- energy, food inputs, minimum wage, etc.
-- Source: CSO CPI + RAI Report 2024
-- -------------------------------------------------------------

CREATE TABLE IF NOT EXISTS operational_cost_index (
    cost_id                 SERIAL          PRIMARY KEY,
    year                    SMALLINT        NOT NULL UNIQUE CHECK (year BETWEEN 2019 AND 2025),
    min_wage_eur_hr         NUMERIC(5,2),   -- national minimum wage per hour
    energy_index            NUMERIC(6,2),   -- energy cost index (base: 2019 = 100)
    food_input_index        NUMERIC(6,2),   -- agricultural/food input price index
    cpi_restaurants_hotels  NUMERIC(6,2),   -- CPI for restaurant & hotel sector
    created_at              TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

-- Known values from CSO and RAI Report 2024
INSERT INTO operational_cost_index
    (year, min_wage_eur_hr, energy_index, food_input_index, cpi_restaurants_hotels)
VALUES
    (2019, 9.80,  100.0, 100.0, 100.0),
    (2020, 10.10, 88.0,  108.0, 97.5),   -- COVID impact, energy dip
    (2021, 10.20, 105.0, 134.0, 99.2),
    (2022, 10.50, 188.0, 182.0, 108.1),  -- energy crisis peak (+88% vs 2019)
    (2023, 11.30, 179.8, 149.0, 115.2),  -- some moderation but still high
    (2024, 12.70, 165.0, 145.0, 119.8)   -- +12.4% min wage Jan 2024
ON CONFLICT (year) DO NOTHING;


-- =============================================================
-- VERIFICATION: check all tables were created successfully
-- =============================================================

SELECT
    table_name,
    (SELECT COUNT(*) FROM information_schema.columns
     WHERE table_schema = 'hospitality'
     AND table_name = t.table_name) AS column_count
FROM information_schema.tables t
WHERE table_schema = 'hospitality'
ORDER BY table_name;
