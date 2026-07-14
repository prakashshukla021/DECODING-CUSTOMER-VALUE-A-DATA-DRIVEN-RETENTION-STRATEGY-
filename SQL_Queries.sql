-- USE my_company;
-- =============================================================================
-- PHASE 2: CUSTOMER SEGMENTATION & SQL ANALYSIS (MySQL 8.0+ VERSION)
-- Project : Decoding Customer Value — A SQL-Driven Retention Strategy
-- Prerequisite: Run setup_mysql.sql first to create + load customer_data
-- =============================================================================
-- MYSQL-SPECIFIC NOTES:
--  - Identifiers with spaces use backticks ` ` instead of double quotes " "
--  - PERCENTILE_CONT is unavailable in MySQL -> replaced with PERCENT_RANK()
--    or NTILE() window functions inside a subquery/CTE
--  - NULLS LAST is unavailable -> handled with ORDER BY expressions
--  - MySQL 8.0+ supports CTEs (WITH) and window functions used below
-- =============================================================================


-- =============================================================================
-- QUERY 1: GENUINE LOYALTY vs. DISCOUNT DEPENDENCY
-- =============================================================================

-- 1A. Overall split: Loyal vs. Discount-Dependent
SELECT
    promo_dependency,
    COUNT(*) AS customer_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_data), 1) AS pct_of_total,
    ROUND(AVG(`Purchase Amount (USD)`), 2) AS avg_purchase_usd,
    ROUND(AVG(`Previous Purchases`), 2)    AS avg_prev_purchases,
    ROUND(AVG(eLTV), 2)                    AS avg_eLTV,
    ROUND(AVG(`Review Rating`), 2)         AS avg_rating
FROM customer_data
GROUP BY promo_dependency
ORDER BY avg_eLTV DESC;


-- 1B. Segment-level promo dependency breakdown
SELECT
    customer_segment,
    COUNT(*)                                 AS segment_size,
    SUM(promo_flag)                          AS promo_users,
    ROUND(AVG(promo_flag) * 100, 1)          AS promo_pct,
    ROUND(AVG(`Previous Purchases`), 1)      AS avg_tenure,
    ROUND(AVG(`Purchase Amount (USD)`), 1)   AS avg_spend,
    ROUND(AVG(eLTV), 0)                      AS avg_eLTV,
    ROUND(AVG(`Review Rating`), 2)           AS avg_rating
FROM customer_data
GROUP BY customer_segment
ORDER BY avg_eLTV DESC;


-- 1C. Subscription vs. Promo dependency paradox
SELECT
    `Subscription Status`,
    promo_dependency,
    COUNT(*) AS cnt,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY `Subscription Status`), 1)
                                              AS pct_within_subscription
FROM customer_data
GROUP BY `Subscription Status`, promo_dependency
ORDER BY `Subscription Status`, promo_dependency;


-- =============================================================================
-- QUERY 2: BEHAVIORAL PATTERNS PREDICTING HIGH CUSTOMER VALUE
-- =============================================================================

-- 2A. Payment method vs. eLTV
SELECT
    `Payment Method`,
    COUNT(*)                                 AS customer_count,
    ROUND(AVG(eLTV), 0)                      AS avg_eLTV,
    ROUND(AVG(`Previous Purchases`), 1)      AS avg_tenure,
    ROUND(AVG(`Purchase Amount (USD)`), 1)   AS avg_spend,
    ROUND(AVG(promo_flag) * 100, 1)          AS promo_pct
FROM customer_data
GROUP BY `Payment Method`
ORDER BY avg_eLTV DESC;


-- 2B. Purchase frequency vs. value tier
SELECT
    `Frequency of Purchases`,
    value_tier,
    COUNT(*)                                 AS cnt,
    ROUND(AVG(eLTV), 0)                      AS avg_eLTV,
    ROUND(AVG(`Previous Purchases`), 1)      AS avg_prev_purchases
FROM customer_data
GROUP BY `Frequency of Purchases`, value_tier
ORDER BY avg_eLTV DESC
LIMIT 20;


-- 2C. BLI quartile profile
SELECT
    BLI_quartile,
    COUNT(*)                                 AS customer_count,
    ROUND(AVG(`Previous Purchases`), 1)      AS avg_prev_purchases,
    ROUND(AVG(`Purchase Amount (USD)`), 1)   AS avg_spend,
    ROUND(AVG(eLTV), 0)                      AS avg_eLTV,
    ROUND(AVG(promo_flag) * 100, 1)          AS promo_pct,
    ROUND(AVG(`Review Rating`), 2)           AS avg_rating,
    ROUND(AVG(CASE WHEN promo_flag = 0 THEN 1.0 ELSE 0 END) * 100, 1) AS organic_pct
FROM customer_data
GROUP BY BLI_quartile
ORDER BY BLI_quartile;


-- 2D. Top 10% of customers by eLTV — what do they look like?
-- MySQL replacement for PERCENTILE_CONT(0.9): use PERCENT_RANK() in a CTE
-- to find the eLTV cutoff at the 90th percentile, then filter on it.
WITH ranked AS (
    SELECT
        *,
        PERCENT_RANK() OVER (ORDER BY eLTV) AS pr
    FROM customer_data
),
cutoff AS (
    -- smallest eLTV whose percent_rank is >= 0.90 (approximates 90th percentile)
    SELECT MIN(eLTV) AS eLTV_90th
    FROM ranked
    WHERE pr >= 0.90
)
SELECT
    ROUND(AVG(Age), 1)                       AS avg_age,
    Gender,
    ROUND(AVG(`Previous Purchases`), 1)      AS avg_prev_purchases,
    ROUND(AVG(`Purchase Amount (USD)`), 1)   AS avg_spend,
    ROUND(AVG(eLTV), 0)                      AS avg_eLTV,
    ROUND(AVG(promo_flag) * 100, 1)          AS promo_pct,
    ROUND(AVG(`Review Rating`), 2)           AS avg_rating
FROM customer_data, cutoff
WHERE eLTV >= cutoff.eLTV_90th
GROUP BY Gender
ORDER BY avg_eLTV DESC;


-- =============================================================================
-- QUERY 3: PRODUCT CATEGORIES LINKED WITH HIGH REPEAT PURCHASING
-- =============================================================================

-- 3A. Category vs. tenure
SELECT
    Category,
    COUNT(*)                                 AS customer_count,
    ROUND(AVG(`Previous Purchases`), 2)      AS avg_prev_purchases,
    ROUND(AVG(BLI), 4)                       AS avg_BLI,
    ROUND(AVG(eLTV), 0)                      AS avg_eLTV,
    ROUND(AVG(promo_flag) * 100, 1)          AS promo_pct,
    ROUND(AVG(`Purchase Amount (USD)`), 1)   AS avg_spend,
    ROUND(AVG(CASE WHEN `Previous Purchases` >= 38 THEN 1.0 ELSE 0 END) * 100, 1)
                                              AS pct_high_tenure
FROM customer_data
GROUP BY Category
ORDER BY avg_prev_purchases DESC;


-- 3B. Item-level analysis within categories
SELECT
    Category,
    `Item Purchased`,
    COUNT(*)                                 AS customer_count,
    ROUND(AVG(`Previous Purchases`), 2)      AS avg_prev_purchases,
    ROUND(AVG(`Purchase Amount (USD)`), 1)   AS avg_spend,
    ROUND(AVG(promo_flag) * 100, 1)          AS promo_pct,
    ROUND(AVG(`Review Rating`), 2)           AS avg_rating
FROM customer_data
GROUP BY Category, `Item Purchased`
HAVING COUNT(*) >= 20
ORDER BY avg_prev_purchases DESC
LIMIT 15;


-- 3C. Season x Category
SELECT
    Season,
    Category,
    COUNT(*)                                 AS customers,
    ROUND(AVG(`Previous Purchases`), 2)      AS avg_prev_purchases,
    ROUND(AVG(promo_flag) * 100, 1)          AS promo_pct,
    ROUND(AVG(eLTV), 0)                      AS avg_eLTV
FROM customer_data
GROUP BY Season, Category
ORDER BY Season, avg_prev_purchases DESC;


-- =============================================================================
-- QUERY 4: GEOGRAPHIES — ORGANIC DEMAND vs. DISCOUNT-DRIVEN VOLUME
-- =============================================================================

-- 4A. State-level opportunity matrix
SELECT
    Location AS state,
    COUNT(*)                                 AS customer_count,
    ROUND(AVG(`Purchase Amount (USD)`), 1)   AS avg_spend,
    ROUND(AVG(eLTV), 0)                      AS avg_eLTV,
    ROUND(AVG(promo_flag) * 100, 1)          AS promo_pct,
    ROUND(AVG(`Previous Purchases`), 1)      AS avg_tenure,
    ROUND(AVG(`Review Rating`), 2)           AS avg_rating,
    ROUND(AVG(`Purchase Amount (USD)`) * (1 - AVG(promo_flag)), 1) AS organic_spend_score,
    CASE
        WHEN AVG(`Purchase Amount (USD)`) >= 60 AND AVG(promo_flag) <= 0.40
            THEN 'High Opportunity'
        WHEN AVG(`Purchase Amount (USD)`) >= 60 AND AVG(promo_flag) > 0.40
            THEN 'High Volume / Discount Risk'
        WHEN AVG(`Purchase Amount (USD)`) < 60  AND AVG(promo_flag) <= 0.40
            THEN 'Emerging Organic'
        ELSE 'Low Priority'
    END                                       AS geo_classification
FROM customer_data
GROUP BY Location
HAVING COUNT(*) >= 10
ORDER BY organic_spend_score DESC
LIMIT 20;


-- 4B. Top 10 organic-demand states (no discount, high spend)
-- MySQL note: NULLS LAST not supported -> use a sort flag that pushes NULL to end
SELECT
    Location AS state,
    COUNT(*)                                                       AS total_customers,
    SUM(CASE WHEN promo_flag = 0 THEN 1 ELSE 0 END)                AS organic_customers,
    ROUND(AVG(CASE WHEN promo_flag = 0 THEN `Purchase Amount (USD)` END), 1)
                                                                    AS organic_avg_spend,
    ROUND(AVG(eLTV), 0)                                            AS avg_eLTV
FROM customer_data
GROUP BY Location
ORDER BY (organic_avg_spend IS NULL) ASC, organic_avg_spend DESC
LIMIT 10;


-- 4C. Category preference by geography
SELECT
    Location,
    Category,
    COUNT(*)                                 AS customers,
    ROUND(AVG(`Purchase Amount (USD)`), 1)   AS avg_spend,
    ROUND(AVG(promo_flag) * 100, 1)          AS promo_pct,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY Location), 1)
                                              AS pct_of_state_customers
FROM customer_data
GROUP BY Location, Category
ORDER BY Location, customers DESC;


-- =============================================================================
-- QUERY 5: IDEAL CUSTOMER PROFILE
-- =============================================================================

-- 5A. Top 20% vs Bottom 80% by eLTV
-- MySQL replacement for PERCENTILE_CONT(0.8): same PERCENT_RANK() pattern as 2D
WITH ranked AS (
    SELECT
        *,
        PERCENT_RANK() OVER (ORDER BY eLTV) AS pr
    FROM customer_data
),
cutoff AS (
    SELECT MIN(eLTV) AS eLTV_80th
    FROM ranked
    WHERE pr >= 0.80
)
SELECT
    'TOP 20%' AS segment,
    COUNT(*)                                 AS n,
    ROUND(AVG(Age), 1)                       AS avg_age,
    MIN(Age)                                 AS min_age,
    MAX(Age)                                 AS max_age,
    ROUND(AVG(`Previous Purchases`), 1)      AS avg_prev_purchases,
    ROUND(AVG(`Purchase Amount (USD)`), 1)   AS avg_spend,
    ROUND(AVG(eLTV), 0)                      AS avg_eLTV,
    ROUND(AVG(promo_flag) * 100, 1)          AS promo_pct,
    ROUND(AVG(subscribed) * 100, 1)          AS subscription_pct,
    ROUND(AVG(`Review Rating`), 2)           AS avg_rating,
    ROUND(AVG(BLI), 4)                       AS avg_BLI,
    ROUND(AVG(ILS), 2)                       AS avg_ILS
FROM customer_data, cutoff
WHERE eLTV >= cutoff.eLTV_80th

UNION ALL

SELECT
    'BOTTOM 80%' AS segment,
    COUNT(*)                                 AS n,
    ROUND(AVG(Age), 1)                       AS avg_age,
    MIN(Age)                                 AS min_age,
    MAX(Age)                                 AS max_age,
    ROUND(AVG(`Previous Purchases`), 1)      AS avg_prev_purchases,
    ROUND(AVG(`Purchase Amount (USD)`), 1)   AS avg_spend,
    ROUND(AVG(eLTV), 0)                      AS avg_eLTV,
    ROUND(AVG(promo_flag) * 100, 1)          AS promo_pct,
    ROUND(AVG(subscribed) * 100, 1)          AS subscription_pct,
    ROUND(AVG(`Review Rating`), 2)           AS avg_rating,
    ROUND(AVG(BLI), 4)                       AS avg_BLI,
    ROUND(AVG(ILS), 2)                       AS avg_ILS
FROM customer_data, cutoff
WHERE eLTV < cutoff.eLTV_80th;


-- 5B. Ideal customer's preferred category and payment method (top 20% by eLTV)
WITH ranked AS (
    SELECT
        *,
        PERCENT_RANK() OVER (ORDER BY eLTV) AS pr
    FROM customer_data
),
cutoff AS (
    SELECT MIN(eLTV) AS eLTV_80th
    FROM ranked
    WHERE pr >= 0.80
)
SELECT
    Category,
    `Payment Method`,
    COUNT(*)                                 AS cnt,
    ROUND(AVG(eLTV), 0)                      AS avg_eLTV,
    ROUND(AVG(`Previous Purchases`), 1)      AS avg_tenure,
    ROUND(AVG(promo_flag) * 100, 1)          AS promo_pct
FROM customer_data, cutoff
WHERE eLTV >= cutoff.eLTV_80th
GROUP BY Category, `Payment Method`
ORDER BY cnt DESC
LIMIT 15;


-- 5C. Age band analysis
SELECT
    CASE
        WHEN Age BETWEEN 18 AND 25 THEN '18-25'
        WHEN Age BETWEEN 26 AND 35 THEN '26-35'
        WHEN Age BETWEEN 36 AND 45 THEN '36-45'
        WHEN Age BETWEEN 46 AND 55 THEN '46-55'
        ELSE '56-70'
    END                                       AS age_band,
    COUNT(*)                                  AS total_customers,
    ROUND(AVG(eLTV), 0)                       AS avg_eLTV,
    ROUND(AVG(`Previous Purchases`), 1)       AS avg_tenure,
    ROUND(AVG(promo_flag) * 100, 1)           AS promo_pct,
    ROUND(AVG(`Review Rating`), 2)            AS avg_rating,
    SUM(CASE WHEN value_tier = 'High' THEN 1 ELSE 0 END) AS high_value_count,
    ROUND(SUM(CASE WHEN value_tier = 'High' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1)
                                               AS pct_high_value
FROM customer_data
GROUP BY age_band
ORDER BY avg_eLTV DESC;


-- =============================================================================
-- BONUS QUERY: PROMO SUNSET TARGETING
-- =============================================================================

-- Safest candidates for promo removal
SELECT
    `Customer ID`,
    Age,
    Gender,
    Category,
    Location,
    `Previous Purchases`,
    `Purchase Amount (USD)`,
    eLTV,
    `Review Rating`,
    satisfaction_flag,
    customer_segment,
    BLI_quartile
FROM customer_data
WHERE promo_flag = 1
  AND `Previous Purchases` >= 38
  AND satisfaction_flag = 'Satisfied'
  AND customer_segment = 'Discount-Dependent Premium'
ORDER BY eLTV DESC
LIMIT 50;

-- Aggregate profile + margin impact estimate
SELECT
    COUNT(*)                                  AS sunset_candidates,
    ROUND(AVG(eLTV), 0)                       AS avg_eLTV,
    ROUND(AVG(`Previous Purchases`), 1)       AS avg_tenure,
    ROUND(AVG(`Review Rating`), 2)            AS avg_rating,
    ROUND(SUM(eLTV), 0)                       AS total_eLTV_at_risk,
    ROUND(SUM(eLTV) * 0.80 - SUM(eLTV), 0)   AS worst_case_eLTV_loss
FROM customer_data
WHERE promo_flag = 1
  AND `Previous Purchases` >= 38
  AND satisfaction_flag = 'Satisfied'
  AND customer_segment = 'Discount-Dependent Premium';