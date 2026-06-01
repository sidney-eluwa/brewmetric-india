-- =============================================================
--  BrewMetric India | Coffee Sales Intelligence Database
--  Author: Sidney Eluwa  |  MySQL 8.0  |  2023-2024
-- =============================================================
 
-- 1 - CREATE DATABASE
 
CREATE DATABASE IF NOT EXISTS brewmetric_india;
 
USE brewmetric_india;

-- 2 - CREATE TABLES

-- City dimension (created first — referenced by customers)
CREATE TABLE IF NOT EXISTS city (
  city_id         INT          NOT NULL,
  city_name       VARCHAR(100) NOT NULL,
  population      BIGINT       NOT NULL,
  estimated_rent  INT          NOT NULL,   -- INR per month
  city_rank       TINYINT      NOT NULL,
  PRIMARY KEY (city_id)
);
 
-- Product dimension
CREATE TABLE IF NOT EXISTS products (
  product_id    INT           NOT NULL,
  product_name  VARCHAR(200)  NOT NULL,
  price         DECIMAL(10,2) NOT NULL,
  PRIMARY KEY (product_id)
);
 
-- Customer dimension
CREATE TABLE IF NOT EXISTS customers (
  customer_id    INT          NOT NULL,
  customer_name  VARCHAR(200) NOT NULL,
  city_id        INT          NOT NULL,
  PRIMARY KEY (customer_id),
  FOREIGN KEY (city_id) REFERENCES city(city_id)
);
 
-- Sales fact table
CREATE TABLE IF NOT EXISTS sales (
  sale_id       INT           NOT NULL,
  sale_date     DATE          NOT NULL,
  product_id    INT           NOT NULL,
  quantity      INT           NOT NULL,
  customer_id   INT           NOT NULL,
  total_amount  DECIMAL(10,2) NOT NULL,
  rating        TINYINT       NOT NULL,
  PRIMARY KEY (sale_id),
  FOREIGN KEY (product_id)  REFERENCES products(product_id),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);


-- 3 - LOAD DATA & VERIFY

-- Load in FK dependency order: city >> products >> customers >> sales
LOAD DATA INFILE "C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/clean/city_clean.csv" -- the MYSQL uploads file path on your system
  INTO TABLE city FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS;
 
LOAD DATA INFILE "C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/clean/products_clean.csv"
  INTO TABLE products FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS;
 
LOAD DATA INFILE "C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/clean/customers_clean.csv"
  INTO TABLE customers FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS;
 
LOAD DATA INFILE "C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/clean/sales_clean.csv"
  INTO TABLE sales FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS;
 
-- Verify row counts
SELECT 'city' AS tbl, COUNT(*) AS rws FROM city
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'customers', COUNT(*) FROM customers
UNION ALL SELECT 'sales', COUNT(*) FROM sales;


-- 4. ANALYSIS QUERIES

-- QUERY 1 [CB] — Overall Business Summary
-- Business Question: What is the total 2023 financial performance?
 
SELECT
  COUNT(sale_id)                           AS total_orders,
  COUNT(DISTINCT customer_id)              AS unique_customers,
  COUNT(DISTINCT product_id)               AS products_sold,
  ROUND(SUM(total_amount), 0)              AS total_revenue_inr,
  ROUND(AVG(total_amount), 0)              AS avg_order_value_inr,
  ROUND(SUM(total_amount) * 0.45, 0)       AS est_gross_profit_inr,
  ROUND(AVG(rating), 1)                    AS overall_avg_rating
FROM sales;

-- QUERY 2 [CB] — City-Level Cost-Benefit Analysis (Core Query)

-- Business Question: Which cities generate the highest return relative to estimated market cost (rent proxy)?

SELECT
  ci.city_name,
  ci.city_rank,
  ci.population,
  ci.estimated_rent,
  COUNT(DISTINCT s.customer_id)                       AS active_customers,
  COUNT(s.sale_id)                                    AS total_orders,
  ROUND(SUM(s.total_amount), 0)                       AS total_revenue,
  ROUND(SUM(s.total_amount) * 0.45, 0)                AS est_gross_profit,
  ROUND(AVG(s.total_amount), 0)                       AS avg_order_value,
  -- Cost-Benefit Index: revenue earned per INR of monthly rent
  ROUND(SUM(s.total_amount) / ci.estimated_rent, 1)   AS revenue_per_rent_unit,
  -- Revenue per customer
  ROUND(SUM(s.total_amount) / COUNT(DISTINCT
        s.customer_id), 0)                            AS revenue_per_customer
FROM sales s
JOIN customers cu ON s.customer_id = cu.customer_id
JOIN city ci       ON cu.city_id   = ci.city_id
GROUP BY ci.city_id, ci.city_name, ci.city_rank,
         ci.population, ci.estimated_rent
ORDER BY total_revenue DESC;

-- QUERY 3 [MP] — Market Penetration Analysis

-- Business Question: Which large-population cities are under-penetrated relative to their market potential?
 
WITH city_customers AS (
  SELECT city_id, COUNT(*) AS customer_count
  FROM customers
  GROUP BY city_id
)
SELECT
  ci.city_name,
  ci.city_rank,
  ci.population,
  ci.estimated_rent,
  cc.customer_count,
  COUNT(s.sale_id)                                    AS total_orders,
  ROUND(SUM(s.total_amount), 0)                       AS total_revenue,
  -- Penetration Rate: customers per 100,000 population
  ROUND(cc.customer_count / ci.population * 100000, 2) AS penetration_per_100k,
  -- Revenue Potential Index: population / 1M × avg order value
  ROUND(ci.population / 1000000 *
        AVG(s.total_amount), 0)                       AS revenue_potential_index
FROM city ci
JOIN city_customers cc  ON ci.city_id = cc.city_id
JOIN customers cu       ON cu.city_id = ci.city_id
JOIN sales s            ON s.customer_id = cu.customer_id
GROUP BY ci.city_id, ci.city_name, ci.city_rank,
         ci.population, ci.estimated_rent, cc.customer_count
ORDER BY ci.population DESC;

-- QUERY 4 [CS] — Customer Satisfaction by City

-- Business Question: Which cities have the highest / lowest satisfaction and does it correlate with order value or volume?

SELECT
  ci.city_name,
  COUNT(s.sale_id)                                    AS total_orders,
  ROUND(AVG(s.rating), 2)                             AS avg_rating,
  SUM(CASE WHEN s.rating >= 4 THEN 1 ELSE 0 END)      AS satisfied_orders,
  SUM(CASE WHEN s.rating = 3  THEN 1 ELSE 0 END)      AS neutral_orders,
  SUM(CASE WHEN s.rating <= 2 THEN 1 ELSE 0 END)      AS dissatisfied_orders,
  ROUND(SUM(CASE WHEN s.rating >= 4 THEN 1 ELSE 0 END)
        / COUNT(s.sale_id) * 100, 1)                  AS satisfaction_rate_pct,
  ROUND(AVG(s.total_amount), 0)                       AS avg_order_value,
  RANK() OVER (ORDER BY AVG(s.rating) DESC)           AS satisfaction_rank
FROM sales s
JOIN customers cu ON s.customer_id = cu.customer_id
JOIN city ci       ON cu.city_id   = ci.city_id
GROUP BY ci.city_id, ci.city_name
ORDER BY avg_rating DESC;

-- QUERY 5 [CS] — Product Satisfaction & Revenue Performance

-- Business Question: Which products have the best combination of revenue and customer satisfaction?

SELECT
  p.product_name,
  -- Category assignment
  CASE
    WHEN p.product_id IN (1,2,3,4,5,7,8,9,11,13)
      THEN 'Coffee Beverages'
    WHEN p.product_id IN (6,15,16,18,19,20,21)
      THEN 'Equipment & Accessories'
    WHEN p.product_id IN (12,14)
      THEN 'Syrups & Flavourings'
    ELSE 'Lifestyle & Gifting'
  END                                                  AS category,
  p.price                                              AS unit_price,
  COUNT(s.sale_id)                                     AS total_orders,
  SUM(s.quantity)                                      AS units_sold,
  ROUND(SUM(s.total_amount), 0)                        AS total_revenue,
  ROUND(SUM(s.total_amount) * 0.45, 0)                 AS est_gross_profit,
  ROUND(AVG(s.rating), 2)                              AS avg_rating,
  ROUND(AVG(s.total_amount), 0)                        AS avg_order_value,
  RANK() OVER (ORDER BY SUM(s.total_amount) DESC)      AS revenue_rank,
  RANK() OVER (ORDER BY AVG(s.rating) DESC)            AS satisfaction_rank
FROM sales s
JOIN products p ON s.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.price
ORDER BY total_revenue DESC;


-- QUERY 6 [MP] — Market Gap Analysis: Population vs Revenue Rank

-- Business Question: Which cities are "punching below their weight" — high population rank but low revenue rank?

WITH city_revenue AS (
  SELECT
    cu.city_id,
    ROUND(SUM(s.total_amount), 0)  AS total_revenue,
    COUNT(s.sale_id)               AS total_orders
  FROM sales s
  JOIN customers cu ON s.customer_id = cu.customer_id
  GROUP BY cu.city_id
)
SELECT
  ci.city_name,
  ci.city_rank                                              AS population_rank,
  RANK() OVER (ORDER BY cr.total_revenue DESC)              AS revenue_rank,
  -- Gap: negative = under-performing vs population potential
	CAST(ci.city_rank AS SIGNED) - 
    CAST(RANK() OVER (ORDER BY cr.total_revenue DESC) AS SIGNED) AS rank_gap,
  ci.population,
  cr.total_revenue,
  ci.estimated_rent,
  -- Opportunity Score: large population, low penetration = high score
  ROUND(ci.population / 1000000 *
        (COUNT(*) OVER() - RANK() OVER (ORDER BY cr.total_revenue DESC) + 1), 1) AS opportunity_score
FROM city ci
JOIN city_revenue cr ON ci.city_id = cr.city_id
ORDER BY rank_gap DESC;

-- QUERY 7 [CS] — Satisfaction vs Order Value Correlation

-- Business Question: Do higher-value orders receive better ratings?

SELECT
  CASE
    WHEN total_amount < 3000  THEN 'Under ₹3,000'
    WHEN total_amount < 6000  THEN '₹3,000–5,999'
    WHEN total_amount < 10000 THEN '₹6,000–9,999'
    WHEN total_amount < 15000 THEN '₹10,000–14,999'
    ELSE '₹15,000+'
  END                               AS order_value_band,
  COUNT(sale_id)                    AS orders,
  ROUND(AVG(total_amount), 0)       AS avg_order_value,
  ROUND(AVG(rating), 2)             AS avg_rating,
  SUM(CASE WHEN rating >= 4 THEN 1 ELSE 0 END) AS satisfied_count,
  ROUND(SUM(CASE WHEN rating >= 4 THEN 1 ELSE 0 END)
        / COUNT(*) * 100, 1)        AS satisfaction_rate_pct
FROM sales
GROUP BY order_value_band
ORDER BY MIN(total_amount);

-- QUERY 8 [CB] — Monthly Revenue Trend & Growth Rate

-- Business Question: How does revenue trend month-on-month across 2023?

WITH monthly AS (
  SELECT
    YEAR(sale_date)                       AS yr,
    MONTH(sale_date)                      AS mn,
    DATE_FORMAT(sale_date, '%b %Y')       AS month_label,
    ROUND(SUM(total_amount), 0)           AS monthly_revenue,
    COUNT(sale_id)                        AS monthly_orders,
    ROUND(AVG(rating), 2)                 AS monthly_avg_rating
  FROM sales
  WHERE YEAR(sale_date) = 2023
  GROUP BY yr, mn, month_label
)
SELECT
  month_label,
  monthly_revenue,
  monthly_orders,
  monthly_avg_rating,
  LAG(monthly_revenue) OVER (ORDER BY yr, mn)    						AS prev_month_revenue,
  ROUND(
    (monthly_revenue - LAG(monthly_revenue) OVER (ORDER BY yr, mn))
    / LAG(monthly_revenue) OVER (ORDER BY yr, mn) * 100,1)              AS mom_growth_pct
FROM monthly
ORDER BY yr, mn;

-- QUERY 9 [MP] — Top Customers by Revenue (Customer Lifetime Value)

-- Business Question: Who are the highest-value customers and in which cities do they cluster?

SELECT
  cu.customer_name,
  ci.city_name,
  ci.city_rank,
  COUNT(s.sale_id)                         AS total_orders,
  ROUND(SUM(s.total_amount), 0)             AS total_revenue,
  ROUND(AVG(s.total_amount), 0)             AS avg_order_value,
  ROUND(AVG(s.rating), 2)                   AS avg_rating,
  RANK() OVER (ORDER BY SUM(s.total_amount) DESC)  AS revenue_rank
FROM sales s
JOIN customers cu ON s.customer_id = cu.customer_id
JOIN city ci       ON cu.city_id   = ci.city_id
GROUP BY cu.customer_id, cu.customer_name, ci.city_name, ci.city_rank
ORDER BY total_revenue DESC
LIMIT 50;

-- QUERY 10 [CB+CS] — City Investment Priority Matrix

-- Business Question: Combining cost-benefit and satisfaction, which cities should receive the most investment attention?
-- Output: Quadrant classification for Power BI scatter chart

WITH city_metrics AS (
  SELECT
    ci.city_name,
    ci.city_rank,
    ci.population,
    ci.estimated_rent,
    COUNT(DISTINCT s.customer_id)                        AS customers,
    COUNT(s.sale_id)                                     AS orders,
    ROUND(SUM(s.total_amount), 0)                        AS revenue,
    ROUND(AVG(s.rating), 2)                              AS avg_rating,
    ROUND(SUM(s.total_amount) / ci.estimated_rent, 1)    AS cb_index,
    ROUND(COUNT(DISTINCT s.customer_id)
          / ci.population * 100000, 2)                   AS penetration
  FROM sales s
  JOIN customers cu ON s.customer_id = cu.customer_id
  JOIN city ci       ON cu.city_id   = ci.city_id
  GROUP BY ci.city_id, ci.city_name, ci.city_rank, ci.population, ci.estimated_rent
)
SELECT
  city_name, city_rank, population, estimated_rent,
  customers, orders, revenue, avg_rating,
  cb_index, penetration,
  -- Quadrant Classification
  CASE
    WHEN cb_index >= 400 AND avg_rating >= 4.0
      THEN 'STAR — Protect & Scale'
    WHEN cb_index >= 400 AND avg_rating < 4.0
      THEN 'CASH COW — Improve Satisfaction'
    WHEN cb_index < 400 AND avg_rating >= 4.0
      THEN 'RISING STAR — Expand Reach'
    ELSE
      'LAGGARD — Review Strategy'
  END AS city_quadrant
FROM city_metrics
ORDER BY cb_index DESC;

-- QUERY 11 [CS] — Rating Distribution by Product Category

-- Business Question: Do certain product categories drive higher satisfaction?

SELECT
  CASE
    WHEN p.product_id IN (1,2,3,4,5,7,8,9,11,13)  THEN 'Coffee Beverages'
    WHEN p.product_id IN (6,15,16,18,19,20,21)    THEN 'Equipment & Accessories'
    WHEN p.product_id IN (12,14)                  THEN 'Syrups & Flavourings'
    ELSE 'Lifestyle & Gifting'
  END                                              AS category,
  COUNT(s.sale_id)                                 AS total_orders,
  ROUND(AVG(s.rating), 2)                          AS avg_rating,
  SUM(CASE WHEN s.rating = 5 THEN 1 ELSE 0 END)    AS five_star,
  SUM(CASE WHEN s.rating = 4 THEN 1 ELSE 0 END)    AS four_star,
  SUM(CASE WHEN s.rating = 3 THEN 1 ELSE 0 END)    AS three_star,
  SUM(CASE WHEN s.rating = 2 THEN 1 ELSE 0 END)    AS two_star,
  ROUND(SUM(CASE WHEN s.rating >= 4 THEN 1 ELSE 0 END)
        / COUNT(*) * 100, 1)                       AS satisfaction_pct
FROM sales s
JOIN products p ON s.product_id = p.product_id
GROUP BY category
ORDER BY avg_rating DESC;















