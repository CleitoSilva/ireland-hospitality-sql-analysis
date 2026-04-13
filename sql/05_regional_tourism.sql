-- =============================================================
-- PROJECT: Ireland Hospitality Sector SQL Analysis
-- FILE:    05_regional_tourism.sql
-- AUTHOR:  Cleiton Silva
-- DATE:    2026
-- =============================================================
-- DESCRIPTION:
--   Answers Business Question 3:
--   Q3 - What was the relationship between tourism arrivals
--        and business survival rates by region?
--
--   Techniques used: multi-table JOINs, CTEs,
--                    correlation analysis, CASE classification
-- =============================================================

SET search_path TO hospitality;


-- =============================================================
-- QUERY 1: Tourism revenue vs business survival by county
-- Core JOIN between Failte Ireland + CSO data
-- =============================================================

WITH survival_rate AS (
    SELECT
        ea.county_id,
        ea.year,
        SUM(ea.active_enterprises)  AS active,
        COALESCE(SUM(ed.ceased_enterprises), 0) AS closures,
        ROUND(
            100.0 * (1 - COALESCE(SUM(ed.ceased_enterprises), 0)::NUMERIC
            / NULLIF(SUM(ea.active_enterprises), 0))
        , 1)                        AS survival_rate_pct
    FROM enterprise_activity ea
    LEFT JOIN enterprise_deaths ed
        ON  ea.county_id = ed.county_id
        AND ea.sector_id = ed.sector_id
        AND ea.year      = ed.year
    JOIN sectors s ON ea.sector_id = s.sector_id
    WHERE s.is_hospitality = TRUE
    GROUP BY ea.county_id, ea.year
)

SELECT
    c.county_name,
    c.province,
    sr.year,
    sr.active,
    sr.closures,
    sr.survival_rate_pct,
    ta.overseas_visitors,
    ta.domestic_visitors,
    ta.total_revenue_eur_m,
    ta.hotel_occupancy_pct,
    -- Classify counties by tourism dependency
    CASE
        WHEN ta.overseas_visitors > 500000  THEN 'High tourism'
        WHEN ta.overseas_visitors > 100000  THEN 'Medium tourism'
        WHEN ta.overseas_visitors IS NOT NULL THEN 'Low tourism'
        ELSE 'No data'
    END                             AS tourism_tier
FROM survival_rate sr
JOIN counties        c  ON sr.county_id = c.county_id
LEFT JOIN tourism_arrivals ta
    ON  sr.county_id = ta.county_id
    AND sr.year      = ta.year
ORDER BY sr.year DESC, sr.survival_rate_pct DESC;


-- =============================================================
-- QUERY 2: High tourism counties vs low tourism counties
-- Do counties with more tourists have better survival rates?
-- =============================================================

WITH county_tourism_tier AS (
    SELECT
        county_id,
        AVG(overseas_visitors) AS avg_overseas_visitors,
        CASE
            WHEN AVG(overseas_visitors) > 500000 THEN 'High tourism'
            WHEN AVG(overseas_visitors) > 100000 THEN 'Medium tourism'
            ELSE 'Low tourism'
        END AS tourism_tier
    FROM tourism_arrivals
    WHERE year BETWEEN 2019 AND 2023
    GROUP BY county_id
),

survival AS (
    SELECT
        ea.county_id,
        ea.year,
        ROUND(
            100.0 * (1 - COALESCE(SUM(ed.ceased_enterprises), 0)::NUMERIC
            / NULLIF(SUM(ea.active_enterprises), 0))
        , 1) AS survival_rate_pct
    FROM enterprise_activity ea
    LEFT JOIN enterprise_deaths ed
        ON  ea.county_id = ed.county_id
        AND ea.sector_id = ed.sector_id
        AND ea.year      = ed.year
    JOIN sectors s ON ea.sector_id = s.sector_id
    WHERE s.is_hospitality = TRUE
    GROUP BY ea.county_id, ea.year
)

SELECT
    tt.tourism_tier,
    s.year,
    COUNT(DISTINCT s.county_id)         AS counties_in_tier,
    ROUND(AVG(s.survival_rate_pct), 1)  AS avg_survival_rate_pct,
    ROUND(MIN(s.survival_rate_pct), 1)  AS min_survival_rate_pct,
    ROUND(MAX(s.survival_rate_pct), 1)  AS max_survival_rate_pct
FROM survival s
JOIN county_tourism_tier tt ON s.county_id = tt.county_id
GROUP BY tt.tourism_tier, s.year
ORDER BY s.year, tt.tourism_tier;


-- =============================================================
-- QUERY 3: Hotel occupancy vs closure rate
-- As occupancy rises, do closures fall?
-- =============================================================

SELECT
    c.county_name,
    ta.year,
    ta.hotel_occupancy_pct,
    ROUND(
        100.0 * SUM(ed.ceased_enterprises)
        / NULLIF(SUM(ea.active_enterprises), 0)
    , 2)                            AS closure_rate_pct,
    -- Label the occupancy level
    CASE
        WHEN ta.hotel_occupancy_pct >= 80 THEN 'High (80%+)'
        WHEN ta.hotel_occupancy_pct >= 60 THEN 'Medium (60-79%)'
        WHEN ta.hotel_occupancy_pct IS NOT NULL THEN 'Low (<60%)'
        ELSE 'No data'
    END                             AS occupancy_band
FROM tourism_arrivals ta
JOIN counties c ON ta.county_id = c.county_id
JOIN enterprise_activity ea
    ON  ta.county_id = ea.county_id
    AND ta.year      = ea.year
LEFT JOIN enterprise_deaths ed
    ON  ea.county_id = ed.county_id
    AND ea.sector_id = ed.sector_id
    AND ea.year      = ed.year
JOIN sectors s ON ea.sector_id = s.sector_id
WHERE s.is_hospitality = TRUE
GROUP BY c.county_name, ta.year, ta.hotel_occupancy_pct
ORDER BY ta.year, ta.hotel_occupancy_pct DESC NULLS LAST;


-- =============================================================
-- QUERY 4: Dublin deep-dive
-- Ireland's largest hospitality market — full picture
-- =============================================================

SELECT
    c.county_name,
    ea.year,
    SUM(ea.active_enterprises)              AS active_enterprises,
    SUM(ea.persons_employed)                AS persons_employed,
    COALESCE(SUM(ed.ceased_enterprises), 0) AS closures,
    ta.overseas_visitors,
    ta.total_revenue_eur_m,
    ta.hotel_occupancy_pct,
    oc.min_wage_eur_hr,
    oc.energy_index
FROM enterprise_activity ea
JOIN counties c ON ea.county_id = c.county_id
JOIN sectors  s ON ea.sector_id = s.sector_id
LEFT JOIN enterprise_deaths ed
    ON  ea.county_id = ed.county_id
    AND ea.sector_id = ed.sector_id
    AND ea.year      = ed.year
LEFT JOIN tourism_arrivals ta
    ON  ea.county_id = ta.county_id
    AND ea.year      = ta.year
LEFT JOIN operational_cost_index oc ON ea.year = oc.year
WHERE c.county_name    = 'Dublin'
  AND s.is_hospitality = TRUE
GROUP BY c.county_name, ea.year, ta.overseas_visitors,
         ta.total_revenue_eur_m, ta.hotel_occupancy_pct,
         oc.min_wage_eur_hr, oc.energy_index
ORDER BY ea.year;


-- =============================================================
-- QUERY 5: Final summary — key findings table
-- Portfolio-ready output: one row per year, full picture
-- =============================================================

WITH yearly_summary AS (
    SELECT
        ea.year,
        SUM(ea.active_enterprises)              AS total_active,
        SUM(ea.persons_employed)                AS total_employed,
        COALESCE(SUM(ed.ceased_enterprises), 0) AS total_closures,
        COALESCE(SUM(eb.new_enterprises),    0) AS total_births,
        ROUND(
            100.0 * COALESCE(SUM(ed.ceased_enterprises), 0)
            / NULLIF(SUM(ea.active_enterprises), 0)
        , 2)                                    AS closure_rate_pct
    FROM enterprise_activity ea
    LEFT JOIN enterprise_deaths ed
        ON  ea.county_id = ea.county_id
        AND ea.sector_id = ed.sector_id
        AND ea.year      = ed.year
    LEFT JOIN enterprise_births eb
        ON  ea.county_id = eb.county_id
        AND ea.sector_id = eb.sector_id
        AND ea.year      = eb.year
    JOIN sectors s ON ea.sector_id = s.sector_id
    WHERE s.is_hospitality = TRUE
    GROUP BY ea.year
)

SELECT
    ys.year,
    ys.total_active,
    ys.total_employed,
    ys.total_closures,
    ys.total_births,
    ys.closure_rate_pct,
    oc.min_wage_eur_hr,
    oc.energy_index,
    -- Recovery index vs 2019
    ROUND(
        100.0 * ys.total_active
        / NULLIF(FIRST_VALUE(ys.total_active) OVER (ORDER BY ys.year), 0)
    , 1)                            AS enterprise_index_vs_2019,
    -- Sector health label
    CASE
        WHEN ys.total_births > ys.total_closures THEN 'Growing'
        WHEN ys.total_births < ys.total_closures THEN 'Contracting'
        ELSE 'Stable'
    END                             AS sector_health
FROM yearly_summary ys
JOIN operational_cost_index oc ON ys.year = oc.year
ORDER BY ys.year;
