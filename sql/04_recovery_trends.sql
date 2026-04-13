-- =============================================================
-- PROJECT: Ireland Hospitality Sector SQL Analysis
-- FILE:    04_recovery_trends.sql
-- AUTHOR:  Cleiton Silva
-- DATE:    2025
-- =============================================================
-- DESCRIPTION:
--   Answers Business Question 2:
--   Q2 - How did hotels compare to restaurants in recovery speed?
--
--   Techniques used: Window Functions (LAG, RANK, running totals),
--                    CTEs, YoY growth, indexed comparisons to 2019
-- =============================================================

SET search_path TO hospitality;


-- =============================================================
-- QUERY 1: Year-over-year enterprise growth by sub-sector
-- Uses LAG() to calculate change vs previous year
-- =============================================================

WITH sector_yearly AS (
    SELECT
        s.sector_name,
        s.nace_code,
        ea.year,
        SUM(ea.active_enterprises) AS active_enterprises,
        SUM(ea.persons_employed)   AS persons_employed
    FROM enterprise_activity ea
    JOIN sectors s ON ea.sector_id = s.sector_id
    WHERE s.is_hospitality = TRUE
    GROUP BY s.sector_name, s.nace_code, ea.year
)

SELECT
    sector_name,
    nace_code,
    year,
    active_enterprises,
    persons_employed,
    -- YoY change in enterprise count
    active_enterprises - LAG(active_enterprises) OVER (
        PARTITION BY sector_name ORDER BY year
    )                                                   AS yoy_change,
    -- YoY percentage change
    ROUND(
        100.0 * (active_enterprises - LAG(active_enterprises) OVER (
            PARTITION BY sector_name ORDER BY year
        ))
        / NULLIF(LAG(active_enterprises) OVER (
            PARTITION BY sector_name ORDER BY year
        ), 0)
    , 1)                                                AS yoy_pct_change
FROM sector_yearly
ORDER BY sector_name, year;


-- =============================================================
-- QUERY 2: Recovery index vs 2019 baseline
-- 2019 = 100. Values above 100 = full recovery, below = not yet
-- This is the key chart for the portfolio
-- =============================================================

WITH base_2019 AS (
    SELECT
        s.sector_name,
        SUM(ea.active_enterprises) AS base_active,
        SUM(ea.persons_employed)   AS base_employed
    FROM enterprise_activity ea
    JOIN sectors s ON ea.sector_id = s.sector_id
    WHERE s.is_hospitality = TRUE
      AND ea.year = 2019
    GROUP BY s.sector_name
),

sector_yearly AS (
    SELECT
        s.sector_name,
        ea.year,
        SUM(ea.active_enterprises) AS active_enterprises,
        SUM(ea.persons_employed)   AS persons_employed
    FROM enterprise_activity ea
    JOIN sectors s ON ea.sector_id = s.sector_id
    WHERE s.is_hospitality = TRUE
    GROUP BY s.sector_name, ea.year
)

SELECT
    sy.sector_name,
    sy.year,
    sy.active_enterprises,
    sy.persons_employed,
    -- Recovery index (2019 = 100)
    ROUND(100.0 * sy.active_enterprises / NULLIF(b.base_active,   0), 1) AS enterprise_recovery_index,
    ROUND(100.0 * sy.persons_employed   / NULLIF(b.base_employed, 0), 1) AS employment_recovery_index
FROM sector_yearly sy
JOIN base_2019 b ON sy.sector_name = b.sector_name
ORDER BY sy.sector_name, sy.year;


-- =============================================================
-- QUERY 3: Birth-to-death ratio per year (Q5)
-- Ratio > 1 means more openings than closures = healthy
-- Ratio < 1 means more closures than openings = contraction
-- =============================================================

WITH births AS (
    SELECT
        eb.year,
        SUM(eb.new_enterprises) AS new_businesses
    FROM enterprise_births eb
    JOIN sectors s ON eb.sector_id = s.sector_id
    WHERE s.is_hospitality = TRUE
    GROUP BY eb.year
),

deaths AS (
    SELECT
        ed.year,
        SUM(ed.ceased_enterprises) AS closed_businesses
    FROM enterprise_deaths ed
    JOIN sectors s ON ed.sector_id = s.sector_id
    WHERE s.is_hospitality = TRUE
    GROUP BY ed.year
)

SELECT
    b.year,
    b.new_businesses,
    d.closed_businesses,
    b.new_businesses - d.closed_businesses          AS net_change,
    ROUND(
        b.new_businesses::NUMERIC
        / NULLIF(d.closed_businesses, 0)
    , 2)                                            AS birth_to_death_ratio,
    CASE
        WHEN b.new_businesses > d.closed_businesses THEN 'Growing'
        WHEN b.new_businesses < d.closed_businesses THEN 'Contracting'
        ELSE 'Stable'
    END                                             AS sector_health
FROM births b
JOIN deaths d ON b.year = d.year
ORDER BY b.year;


-- =============================================================
-- QUERY 4: Cumulative net change in enterprises since 2019
-- Running total shows the full COVID impact and recovery arc
-- =============================================================

WITH net_annual AS (
    SELECT
        b.year,
        SUM(b.new_enterprises)    AS births,
        SUM(d.ceased_enterprises) AS deaths,
        SUM(b.new_enterprises) - SUM(d.ceased_enterprises) AS net_change
    FROM enterprise_births b
    JOIN enterprise_deaths d
        ON  b.year      = d.year
        AND b.county_id = d.county_id
        AND b.sector_id = d.sector_id
        AND b.size_id   = d.size_id
    JOIN sectors s ON b.sector_id = s.sector_id
    WHERE s.is_hospitality = TRUE
    GROUP BY b.year
)

SELECT
    year,
    births,
    deaths,
    net_change,
    SUM(net_change) OVER (ORDER BY year ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                                AS cumulative_net_change
FROM net_annual
ORDER BY year;


-- =============================================================
-- QUERY 5: Recovery speed ranking by county
-- Which counties bounced back fastest after 2020?
-- Compares 2022 vs 2020 enterprise count (trough to peak)
-- =============================================================

WITH county_2020 AS (
    SELECT
        ea.county_id,
        SUM(ea.active_enterprises) AS active_2020
    FROM enterprise_activity ea
    JOIN sectors s ON ea.sector_id = s.sector_id
    WHERE s.is_hospitality = TRUE AND ea.year = 2020
    GROUP BY ea.county_id
),

county_2022 AS (
    SELECT
        ea.county_id,
        SUM(ea.active_enterprises) AS active_2022
    FROM enterprise_activity ea
    JOIN sectors s ON ea.sector_id = s.sector_id
    WHERE s.is_hospitality = TRUE AND ea.year = 2022
    GROUP BY ea.county_id
)

SELECT
    c.county_name,
    c.province,
    c20.active_2020,
    c22.active_2022,
    c22.active_2022 - c20.active_2020                  AS recovery_gain,
    ROUND(
        100.0 * (c22.active_2022 - c20.active_2020)
        / NULLIF(c20.active_2020, 0)
    , 1)                                                AS recovery_pct,
    RANK() OVER (
        ORDER BY
            100.0 * (c22.active_2022 - c20.active_2020)
            / NULLIF(c20.active_2020, 0) DESC
    )                                                   AS recovery_rank
FROM county_2020 c20
JOIN county_2022 c22 ON c20.county_id = c22.county_id
JOIN counties    c   ON c20.county_id = c.county_id
ORDER BY recovery_rank;
