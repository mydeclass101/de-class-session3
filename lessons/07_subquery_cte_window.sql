-- =====================================================================
--  บทที่ 7: Subquery · CTE · Window functions (เครื่องมือหลักของ DE)
--  ข้อมูล: ecommerce (อ่านอย่างเดียว)
-- =====================================================================
USE ecommerce;

-- ---------------------------------------------------------------------
-- 7.1 Subquery
-- ---------------------------------------------------------------------
-- scalar subquery: ค่าเดียว ใช้เทียบได้
SELECT order_number, total_amount
FROM orders
WHERE status = 'completed'
  AND total_amount > 10 * (SELECT AVG(total_amount) FROM orders WHERE status = 'completed')
ORDER BY total_amount DESC
LIMIT 10;

-- IN (subquery): ลูกค้าที่เคยซื้อสินค้าหมวด Pet Supplies
SELECT COUNT(*) AS pet_owners
FROM customers
WHERE customer_id IN (
    SELECT o.customer_id
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN products p     ON p.product_id = oi.product_id
    JOIN categories sub ON sub.category_id = p.category_id
    JOIN categories top ON top.category_id = sub.parent_category_id
    WHERE top.category_code = 'PET');

-- EXISTS: order ที่จ่ายเงินไม่ผ่านอย่างน้อย 1 ครั้ง แต่สุดท้ายจ่ายสำเร็จ
SELECT COUNT(*) AS recovered_orders
FROM orders o
WHERE o.paid_at IS NOT NULL
  AND EXISTS (SELECT 1 FROM payments p WHERE p.order_id = o.order_id AND p.status = 'failed');

-- ---------------------------------------------------------------------
-- 7.2 CTE (WITH): แตก query ยาวเป็นขั้น ๆ อ่านง่ายเหมือน pipeline ย่อย
-- ---------------------------------------------------------------------
WITH monthly AS (                                  -- ขั้น 1: สรุปรายเดือน
    SELECT DATE_FORMAT(ordered_at, '%Y-%m') AS month, SUM(total_amount) AS gmv
    FROM orders
    WHERE status <> 'cancelled'
    GROUP BY month
),
ranked AS (                                        -- ขั้น 2: ใช้ผลของขั้น 1
    SELECT month, gmv, RANK() OVER (ORDER BY gmv DESC) AS rnk
    FROM monthly
)
SELECT * FROM ranked WHERE rnk <= 3;               -- 3 เดือนที่ขายดีที่สุด

-- ---------------------------------------------------------------------
-- 7.3 Window function: คำนวณ "ข้ามแถว" โดยไม่ยุบแถวแบบ GROUP BY
--     รูปแบบ: FUNC() OVER (PARTITION BY ... ORDER BY ... [ROWS ...])
-- ---------------------------------------------------------------------
-- (ก) % ของทั้งหมด: SUM() OVER () = ผลรวมทั้งตาราง
SELECT payment_method, COUNT(*) AS n,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM orders
GROUP BY payment_method;

-- (ข) LAG: เทียบกับแถวก่อนหน้า → การเติบโตเดือนต่อเดือน (MoM)
WITH monthly AS (
    SELECT DATE_FORMAT(ordered_at, '%Y-%m') AS month, SUM(total_amount) AS gmv
    FROM orders WHERE status <> 'cancelled' GROUP BY month
)
SELECT month, gmv,
       LAG(gmv) OVER (ORDER BY month)                                  AS prev_gmv,
       ROUND(100 * (gmv / LAG(gmv) OVER (ORDER BY month) - 1), 1)      AS mom_growth_pct,
       SUM(gmv) OVER (ORDER BY month)                                  AS running_gmv     -- ยอดสะสม
FROM monthly
ORDER BY month;

-- (ค) Moving average 7 วัน (ลด noise ของยอดรายวัน)
WITH daily AS (
    SELECT DATE(ordered_at) AS d, COUNT(*) AS orders
    FROM orders WHERE ordered_at >= '2026-06-01' GROUP BY d
)
SELECT d, orders,
       ROUND(AVG(orders) OVER (ORDER BY d ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1) AS ma_7d
FROM daily
ORDER BY d;

-- (ง) ROW_NUMBER: "เอาแถวล่าสุดของแต่ละกลุ่ม" ⭐ pattern ที่ DE ใช้บ่อยที่สุด (dedup)
--     order ล่าสุดของลูกค้าแต่ละคน
WITH ranked AS (
    SELECT customer_id, order_number, ordered_at, total_amount,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY ordered_at DESC, order_id DESC) AS rn
    FROM orders
)
SELECT customer_id, order_number, ordered_at, total_amount
FROM ranked
WHERE rn = 1
ORDER BY customer_id
LIMIT 20;

-- (จ) RANK / DENSE_RANK: top 3 สินค้าขายดีในแต่ละหมวดหลัก
WITH product_sales AS (
    SELECT top.name_en AS category, p.sku, p.product_name, SUM(oi.line_total) AS revenue
    FROM order_items oi
    JOIN orders o       ON o.order_id = oi.order_id AND o.status <> 'cancelled'
    JOIN products p     ON p.product_id = oi.product_id
    JOIN categories sub ON sub.category_id = p.category_id
    JOIN categories top ON top.category_id = sub.parent_category_id
    GROUP BY top.name_en, p.product_id, p.sku, p.product_name
),
ranked AS (
    SELECT *, DENSE_RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS rnk
    FROM product_sales
)
SELECT category, rnk, sku, product_name, revenue
FROM ranked WHERE rnk <= 3
ORDER BY category, rnk;
--   ROW_NUMBER = 1,2,3,4 (ไม่มีเสมอ) · RANK = 1,2,2,4 · DENSE_RANK = 1,2,2,3

-- (ฉ) LAG ภายในกลุ่ม: ลูกค้ากลับมาซื้อซ้ำห่างกันกี่วัน
WITH gaps AS (
    SELECT customer_id, ordered_at,
           DATEDIFF(ordered_at, LAG(ordered_at) OVER (PARTITION BY customer_id ORDER BY ordered_at)) AS days_since_prev
    FROM orders
    WHERE status <> 'cancelled'
)
SELECT CASE WHEN days_since_prev <= 7 THEN '1) ≤ 7 วัน'
            WHEN days_since_prev <= 30 THEN '2) 8-30 วัน'
            WHEN days_since_prev <= 90 THEN '3) 31-90 วัน'
            ELSE '4) > 90 วัน' END AS gap_bucket,
       COUNT(*) AS repeat_orders
FROM gaps
WHERE days_since_prev IS NOT NULL                   -- order แรกของลูกค้าไม่มีแถวก่อนหน้า
GROUP BY gap_bucket
ORDER BY gap_bucket;

-- (ช) NTILE: แบ่งลูกค้าเป็น 4 กลุ่มตามยอดซื้อ (quartile)
WITH spend AS (
    SELECT customer_id, SUM(total_amount) AS total_spend
    FROM orders WHERE status = 'completed' GROUP BY customer_id
)
SELECT quartile, COUNT(*) AS customers, MIN(total_spend) AS min_spend, MAX(total_spend) AS max_spend,
       ROUND(SUM(total_spend) / (SELECT SUM(total_spend) FROM spend) * 100, 1) AS pct_of_revenue
FROM (SELECT customer_id, total_spend, NTILE(4) OVER (ORDER BY total_spend DESC) AS quartile FROM spend) q
GROUP BY quartile
ORDER BY quartile;

-- ---------------------------------------------------------------------
-- 7.4 Recursive CTE: สร้าง "date spine" (ตารางวันที่ต่อเนื่อง) เติมวันที่ไม่มีข้อมูล
-- ---------------------------------------------------------------------
-- ปัญหา: GROUP BY วันที่ จะ "ไม่มีแถว" ในวันที่ขายไม่ได้เลย → กราฟ/ค่าเฉลี่ยผิด
SET @sku = (SELECT sku FROM products WHERE status = 'active' ORDER BY product_id DESC LIMIT 1);

WITH RECURSIVE days AS (
    SELECT DATE('2026-08-01') AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM days WHERE d < '2026-08-31'
),
sold AS (
    SELECT DATE(o.ordered_at) AS d, SUM(oi.quantity) AS units
    FROM order_items oi
    JOIN orders o   ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    WHERE p.sku = @sku AND o.ordered_at >= '2026-08-01' AND o.ordered_at < '2026-09-01'
    GROUP BY DATE(o.ordered_at)
)
SELECT days.d, COALESCE(sold.units, 0) AS units       -- วันที่ขายไม่ได้ = 0 (ไม่หายไป)
FROM days LEFT JOIN sold ON sold.d = days.d
ORDER BY days.d;

-- สรุปบทที่ 7
--   subquery (scalar / IN / EXISTS) · CTE · window: SUM() OVER, LAG, moving average,
--   ROW_NUMBER (dedup/latest) ⭐, RANK/DENSE_RANK, NTILE · recursive CTE date spine
--   ➡️ ทำ Assignment A4
