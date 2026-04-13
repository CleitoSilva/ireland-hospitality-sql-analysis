-- =============================================================
-- PROJECT: Ireland Hospitality Sector SQL Analysis
-- FILE:    03_analysis_closures.sql
-- AUTHOR:  Cleiton Silva
-- DATE:    2025
-- =============================================================
-- DESCRIPTION:
--   Answers Business Question 1 & 4:
--   Q1 - Which counties had the highest hospitality closure rates?
--   Q4 - Which business size was most affected by closures?
--
--   Techniques used: JOINs, CTEs, GROUP BY, HAVING,
--                    ROUND, NULLIF, derived metrics
-- =============================================================

SET search_path TO hospitality;


-- =============================================================
-- QUERY 1: Total closures per year — hospitality vs all sectors
-- Shows the scale of the crisis in context
-- =============================================================

SELECT
    ed.year,
    SUM(ed.ceased_enterprises)                          AS total_closures_all_sectors,
    SUM(ed.ceased_enterprises) FILTER (
        WHERE s.is_hospitality = TRUE)                  AS hospitality_closures,
    SUM(ed.persons_employed)   FILTER (
        WHERE s.is_hospitality = TRUE)                  AS hospitality_jobs_lost,
    ROUND(
        100.0 * SUM(ed.ceased_enterprises) FILTER (WHERE s.is_hospitality = TRUE)
        / NULLIF(SUM(ed.ceased_enterprises), 0)
    , 1)                                                AS hospitality_pct_of_all_closures
FROM enterprise_deaths ed
JOIN sectors s ON ed.sector_id = s.sector_id
GROUP BY ed.year
ORDER BY ed.year;


-- =============================================================
-- QUERY 2: Closure rate by county — hospitality sector
-- Closure rate = closures / active enterprises * 100
-- Answers Q1: which counties were hit hardest?
-- =============================================================

WITH county_activity AS (
    SELECT
        ea.year,
        ea.county_id,
        SUM(ea.active_enterprises) AS active_enterprises
    FROM enterprise_activity ea
    JOIN sectors s ON ea.sector_id = s.sector_id
    WHERE s.is_hospitality = TRUE
    GROUP BY ea.year, ea.county_id
),

county_deaths AS (
    SELECT
        ed.year,
        ed.county_id,
        SUM(ed.ceased_enterprises) AS closures,
        SUM(ed.persons_employed)   AS jobs_lost
    FROM enterprise_deaths ed
    JOIN sectors s ON ed.sector_id = s.sector_id
    WHERE s.is_hospitality = TRUE
    GROUP BY ed.year, ed.county_id
)

SELECT
    c.county_name,
    c.province,
    ca.year,
    ca.active_enterprises,
    COALESCE(cd.closures,  0)   AS closures,
    COALESCE(cd.jobs_lost, 0)   AS jobs_lost,
    ROUND(
        100.0 * COALESCE(cd.closures, 0)
        / NULLIF(ca.active_enterprises, 0)
    , 2)                        AS closure_rate_pct
FROM county_activity ca
JOIN counties       c  ON ca.county_id = c.county_id
LEFT JOIN county_deaths cd
    ON ca.county_id = cd.county_id
    AND ca.year     = cd.year
ORDER BY ca.year DESC, closure_rate_pct DESC;


-- =============================================================
-- QUERY 3: Top 10 worst-hit counties (2021 peak year)
-- Ready to screenshot for your README/portfolio
-- =============================================================

WITH county_closure_rate AS (
    SELECT
        c.county_name,
        c.province,
        SUM(ea.active_enterprises)  AS active,
        SUM(ed.ceased_enterprises)  AS closures,
        ROUND(
            100.0 * SUM(ed.ceased_enterprises)
            / NULLIF(SUM(ea.active_enterprises), 0)
        , 2)                        AS closure_rate_pct
    FROM enterprise_activity ea
    JOIN enterprise_deaths ed
        ON  ea.county_id = ed.county_id
        AND ea.sector_id = ed.sector_id
        AND ea.year      = ed.year
    JOIN counties c  ON ea.county_id = c.county_id
    JOIN sectors  s  ON ea.sector_id = s.sector_id
    WHERE ea.year          = 2021
      AND s.is_hospitality = TRUE
    GROUP BY c.county_name, c.province
)

SELECT
    RANK() OVER (ORDER BY closure_rate_pct DESC) AS rank,
    county_name,
    province,
    active,
    closures,
    closure_rate_pct
FROM county_closure_rate
WHERE active > 0
ORDER BY closure_rate_pct DESC
LIMIT 10;


-- =============================================================
-- QUERY 4: Closures by sub-sector
-- Hotels vs Restaurants vs Bars — who suffered most?
-- =============================================================

SELECT
    s.sector_name,
    s.nace_code,
    ed.year,
    SUM(ed.ceased_enterprises)  AS total_closures,
    SUM(ed.persons_employed)    AS total_jobs_lost,
    ROUND(AVG(
        100.0 * ed.ceased_enterprises
        / NULLIF(ea.active_enterprises, 0)
    ), 2)                       AS avg_closure_rate_pct
FROM enterprise_deaths ed
JOIN enterprise_activity ea
    ON  ed.county_id = ea.county_id
    AND ed.sector_id = ea.sector_id
    AND ed.year      = ea.year
JOIN sectors s ON ed.sector_id = s.sector_id
WHERE s.is_hospitality = TRUE
GROUP BY s.sector_name, s.nace_code, ed.year
ORDER BY ed.year, total_closures DESC;


-- =============================================================
-- QUERY 5: Closures by business size (Q4)
-- Micro vs Small vs Medium vs Large
-- =============================================================

SELECT
    sc.size_label,
    sc.min_employees,
    ed.year,
    SUM(ed.ceased_enterprises)      AS total_closures,
    SUM(ed.persons_employed)        AS jobs_lost,
    ROUND(
        100.0 * SUM(ed.ceased_enterprises)
        / NULLIF(SUM(SUM(ed.ceased_enterprises)) OVER (PARTITION BY ed.year), 0)
    , 1)                            AS pct_of_year_closures
FROM enterprise_deaths ed
JOIN enterprise_size_classes sc ON ed.size_id   = sc.size_id
JOIN sectors                 s  ON ed.sector_id = s.sector_id
WHERE s.is_hospitality = TRUE
GROUP BY sc.size_label, sc.min_employees, ed.year
ORDER BY ed.year, sc.min_employees;


-- =============================================================
-- QUERY 6: Closure hotspots — county + sub-sector combination
-- Finds the most vulnerable combinations
-- =============================================================

WITH ranked_hotspots AS (
    SELECT
        c.county_name,
        s.sector_name,
        ed.year,
        SUM(ed.ceased_enterprises)  AS closures,
        SUM(ed.persons_employed)    AS jobs_lost,
        RANK() OVER (
            PARTITION BY ed.year
            ORDER BY SUM(ed.ceased_enterprises) DESC
        )                           AS rnk
    FROM enterprise_deaths ed
    JOIN counties c ON ed.county_id = c.county_id
    JOIN sectors  s ON ed.sector_id = s.sector_id
    WHERE s.is_hospitality = TRUE
    GROUP BY c.county_name, s.sector_name, ed.year
)

SELECT
    year,
    rnk         AS rank,
    county_name,
    sector_name,
    closures,
    jobs_lost
FROM ranked_hotspots
WHERE rnk <= 5
ORDER BY year DESC, rnk;


-- =============================================================
-- QUERY 7: Cost pressure vs closure rate correlation
-- Links rising costs (from operational_cost_index)
-- to closure rates — the business story of this project
-- =============================================================

WITH annual_closures AS (
    SELECT
        ed.year,
        SUM(ed.ceased_enterprises) AS total_closures,
        SUM(ea.active_enterprises) AS total_active,
        ROUND(
            100.0 * SUM(ed.ceased_enterprises)
            / NULLIF(SUM(ea.active_enterprises), 0)
        , 2)                       AS closure_rate_pct
    FROM enterprise_deaths ed
    JOIN enterprise_activity ea
        ON  ed.county_id = ea.county_id
        AND ed.sector_id = ea.sector_id
        AND ed.year      = ea.year
    JOIN sectors s ON ed.sector_id = s.sector_id
    WHERE s.is_hospitality = TRUE
    GROUP BY ed.year
)

SELECT
    ac.year,
    ac.total_closures,
    ac.closure_rate_pct,
    oc.min_wage_eur_hr,
    oc.energy_index,
    oc.food_input_index,
    oc.cpi_restaurants_hotels,
    -- Year-over-year change in energy costs
    ROUND(oc.energy_index - LAG(oc.energy_index) OVER (ORDER BY oc.year), 1)
                                   AS energy_index_yoy_change
FROM annual_closures ac
JOIN operational_cost_index oc ON ac.year = oc.year
ORDER BY ac.year;
