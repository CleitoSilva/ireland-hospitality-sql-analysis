-- =============================================================
-- PROJECT: Ireland Hospitality Sector SQL Analysis
-- FILE:    02_analysis.sql (based on real CSO BRA34 data)
-- AUTHOR:  Cleiton Silva
-- DATE:    2025
-- =============================================================
-- Run AFTER 01_create_tables.sql and loading the CSV.
-- All queries use real data from CSO Ireland.
-- =============================================================

SET search_path TO hospitality;


-- =============================================================
-- QUERY 1: National overview — how did the sector evolve?
-- Shows the COVID crash in 2020 and recovery through 2023
-- =============================================================

SELECT
    year,
    SUM(active_enterprises)                             AS total_enterprises,
    SUM(persons_engaged)                                AS total_persons_engaged,
    -- YoY change in enterprises
    SUM(active_enterprises) - LAG(SUM(active_enterprises))
        OVER (ORDER BY year)                            AS enterprise_yoy_change,
    -- YoY % change
    ROUND(
        100.0 * (SUM(active_enterprises) - LAG(SUM(active_enterprises)) OVER (ORDER BY year))
        / NULLIF(LAG(SUM(active_enterprises)) OVER (ORDER BY year), 0)
    , 1)                                                AS enterprise_yoy_pct,
    -- Recovery index vs 2019 baseline
    ROUND(
        100.0 * SUM(active_enterprises)
        / NULLIF(FIRST_VALUE(SUM(active_enterprises)) OVER (ORDER BY year), 0)
    , 1)                                                AS recovery_index_vs_2019
FROM hospitality_county_year
WHERE activity ILIKE '%Accommodation and Food Service%'
GROUP BY year
ORDER BY year;


-- =============================================================
-- QUERY 2: County rankings — most vs least enterprises (2023)
-- =============================================================

SELECT
    RANK() OVER (ORDER BY active_enterprises DESC) AS rank,
    county,
    active_enterprises                             AS enterprises_2023,
    persons_engaged                                AS persons_engaged_2023,
    ROUND(persons_engaged / NULLIF(active_enterprises, 0), 1)
                                                   AS avg_persons_per_enterprise
FROM hospitality_county_year
WHERE year     = 2023
  AND activity ILIKE '%Accommodation and Food Service%'
ORDER BY rank;


-- =============================================================
-- QUERY 3: COVID impact by county — drop from 2019 to 2020
-- Shows which counties lost most enterprises during COVID
-- =============================================================

WITH y2019 AS (
    SELECT county, active_enterprises AS ent_2019, persons_engaged AS persons_2019
    FROM hospitality_county_year
    WHERE year = 2019 AND activity ILIKE '%Accommodation and Food Service%'
),
y2020 AS (
    SELECT county, active_enterprises AS ent_2020, persons_engaged AS persons_2020
    FROM hospitality_county_year
    WHERE year = 2020 AND activity ILIKE '%Accommodation and Food Service%'
)
SELECT
    a.county,
    a.ent_2019,
    b.ent_2020,
    b.ent_2020 - a.ent_2019                          AS enterprise_change,
    ROUND(
        100.0 * (b.ent_2020 - a.ent_2019)
        / NULLIF(a.ent_2019, 0)
    , 1)                                              AS enterprise_change_pct,
    a.persons_2019,
    b.persons_2020,
    b.persons_2020 - a.persons_2019                  AS jobs_change,
    ROUND(
        100.0 * (b.persons_2020 - a.persons_2019)
        / NULLIF(a.persons_2019, 0)
    , 1)                                              AS jobs_change_pct
FROM y2019 a
JOIN y2020 b ON a.county = b.county
ORDER BY jobs_change_pct ASC;  -- worst hit first


-- =============================================================
-- QUERY 4: Full recovery analysis — 2019 vs 2023
-- Which counties fully recovered? Which are still behind?
-- =============================================================

WITH y2019 AS (
    SELECT county, active_enterprises AS ent_2019, persons_engaged AS persons_2019
    FROM hospitality_county_year
    WHERE year = 2019 AND activity ILIKE '%Accommodation and Food Service%'
),
y2023 AS (
    SELECT county, active_enterprises AS ent_2023, persons_engaged AS persons_2023
    FROM hospitality_county_year
    WHERE year = 2023 AND activity ILIKE '%Accommodation and Food Service%'
)
SELECT
    a.county,
    a.ent_2019,
    b.ent_2023,
    b.ent_2023 - a.ent_2019                          AS net_change,
    ROUND(
        100.0 * b.ent_2023 / NULLIF(a.ent_2019, 0)
    , 1)                                              AS recovery_index,   -- 100 = full recovery
    CASE
        WHEN b.ent_2023 > a.ent_2019 * 1.05  THEN 'Strong growth (+5%)'
        WHEN b.ent_2023 >= a.ent_2019        THEN 'Fully recovered'
        WHEN b.ent_2023 >= a.ent_2019 * 0.95 THEN 'Nearly recovered'
        ELSE 'Still below 2019'
    END                                               AS recovery_status,
    ROUND(
        100.0 * (b.persons_2023 - a.persons_2019)
        / NULLIF(a.persons_2019, 0)
    , 1)                                              AS employment_change_pct
FROM y2019 a
JOIN y2023 b ON a.county = b.county
ORDER BY recovery_index DESC;


-- =============================================================
-- QUERY 5: Accommodation vs Food & Beverage comparison
-- Which sub-sector recovered faster?
-- =============================================================

SELECT
    CASE
        WHEN activity ILIKE '%Accommodation (I55)%'  THEN 'Accommodation'
        WHEN activity ILIKE '%Food and Beverage%'    THEN 'Food & Beverage'
    END                                               AS sub_sector,
    year,
    SUM(active_enterprises)                           AS enterprises,
    SUM(persons_engaged)                              AS persons_engaged,
    ROUND(
        100.0 * SUM(active_enterprises)
        / NULLIF(FIRST_VALUE(SUM(active_enterprises))
            OVER (PARTITION BY activity ORDER BY year), 0)
    , 1)                                              AS index_vs_2019
FROM hospitality_county_year
WHERE activity ILIKE '%Accommodation (I55)%'
   OR activity ILIKE '%Food and Beverage%'
GROUP BY activity, year
ORDER BY sub_sector, year;


-- =============================================================
-- QUERY 6: Province-level aggregation
-- Leinster vs Munster vs Connacht vs Ulster — who recovered best?
-- =============================================================

WITH province_map AS (
    SELECT county, CASE
        WHEN county IN ('Co. Dublin','Co. Wicklow','Co. Wexford','Co. Carlow',
                        'Co. Kilkenny','Co. Waterford','Co. Tipperary','Co. Laois',
                        'Co. Offaly','Co. Kildare','Co. Meath','Co. Louth',
                        'Co. Longford','Co. Westmeath') THEN 'Leinster'
        WHEN county IN ('Co. Cork','Co. Kerry','Co. Limerick','Co. Clare') THEN 'Munster'
        WHEN county IN ('Co. Galway','Co. Mayo','Co. Roscommon',
                        'Co. Sligo','Co. Leitrim')         THEN 'Connacht'
        WHEN county IN ('Co. Donegal','Co. Cavan','Co. Monaghan') THEN 'Ulster (ROI)'
    END AS province
    FROM (SELECT DISTINCT county FROM hospitality_county_year) c
)
SELECT
    pm.province,
    h.year,
    SUM(h.active_enterprises)  AS total_enterprises,
    SUM(h.persons_engaged)     AS total_persons_engaged,
    ROUND(
        100.0 * SUM(h.active_enterprises)
        / NULLIF(FIRST_VALUE(SUM(h.active_enterprises))
            OVER (PARTITION BY pm.province ORDER BY h.year), 0)
    , 1)                       AS recovery_index_vs_2019
FROM hospitality_county_year h
JOIN province_map pm ON h.county = pm.county
WHERE h.activity ILIKE '%Accommodation and Food Service%'
  AND pm.province IS NOT NULL
GROUP BY pm.province, h.year
ORDER BY pm.province, h.year;


-- =============================================================
-- QUERY 7: Top 5 / Bottom 5 counties by employment recovery
-- Portfolio-ready ranking table
-- =============================================================

WITH recovery AS (
    SELECT
        county,
        MAX(persons_engaged) FILTER (WHERE year = 2019) AS persons_2019,
        MAX(persons_engaged) FILTER (WHERE year = 2023) AS persons_2023
    FROM hospitality_county_year
    WHERE activity ILIKE '%Accommodation and Food Service%'
    GROUP BY county
)
SELECT
    'Top 5 - Best Recovery'        AS category,
    RANK() OVER (ORDER BY (persons_2023 - persons_2019) / NULLIF(persons_2019, 0) DESC) AS rank,
    county,
    persons_2019::INT,
    persons_2023::INT,
    (persons_2023 - persons_2019)::INT                  AS jobs_gained,
    ROUND(100.0 * (persons_2023 - persons_2019) / NULLIF(persons_2019, 0), 1) AS pct_change
FROM recovery
WHERE persons_2019 > 0
ORDER BY pct_change DESC
LIMIT 5;
