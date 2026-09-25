-- =====================================================================
--  บทที่ 6: ข้อมูลจริง: สำรวจ source ใหม่แบบ Data Engineer
--  database ecommerce: ร้านค้าออนไลน์ 25 ตาราง, หลายล้านแถว, อ่านได้อย่างเดียว
--  💡 เป็นแค่ "mini shop บทที่ 5" เวอร์ชันใหญ่: customers / products / orders / order_items / payments
-- =====================================================================
USE ecommerce;

-- ⚠️ กฎเหล็กบนตารางใหญ่
--   1) ใส่ LIMIT เวลาดูตัวอย่าง    2) กรองช่วงเวลาเมื่อทำได้    3) ห้าม SELECT * ใน pipeline

-- ---------------------------------------------------------------------
-- 6.1 มีตารางอะไรบ้าง ใหญ่แค่ไหน
-- ---------------------------------------------------------------------
SHOW TABLES;

SELECT table_name,
       table_rows                                        AS approx_rows,   -- ค่าประมาณ (เร็ว)
       ROUND((data_length + index_length) / 1024 / 1024) AS size_mb,
       table_comment
FROM information_schema.tables
WHERE table_schema = 'ecommerce'
ORDER BY table_rows DESC;

-- นับจริง (ช้ากว่า แต่แม่นยำ)
SELECT (SELECT COUNT(*) FROM customers)   AS customers,
       (SELECT COUNT(*) FROM products)    AS products,
       (SELECT COUNT(*) FROM orders)      AS orders,
       (SELECT COUNT(*) FROM order_items) AS order_items;

-- ---------------------------------------------------------------------
-- 6.2 โครงสร้างและความสัมพันธ์ (ER diagram จาก metadata)
-- ---------------------------------------------------------------------
DESCRIBE orders;

-- Foreign keys ทั้งหมด: ตารางไหนอ้างอิงตารางไหน
SELECT table_name, column_name, referenced_table_name, referenced_column_name
FROM information_schema.key_column_usage
WHERE table_schema = 'ecommerce' AND referenced_table_name IS NOT NULL
ORDER BY table_name;

-- ค่าที่เป็นไปได้ของคอลัมน์สถานะ (ดูจาก CHECK constraint)
SELECT constraint_name, check_clause
FROM information_schema.check_constraints
WHERE constraint_schema = 'ecommerce' AND constraint_name LIKE 'ck_orders%';

-- ---------------------------------------------------------------------
-- 6.3 ดูตัวอย่างข้อมูล + ทำความเข้าใจ business key
-- ---------------------------------------------------------------------
SELECT customer_id, customer_code, first_name, last_name, membership_tier, status, registered_at
FROM customers ORDER BY customer_id LIMIT 5;

-- SKU = <หมวดย่อย>-<แบรนด์>-<เลขรัน> → แตกเป็นส่วน ๆ แล้วเทียบกับตาราง master
SELECT p.sku,
       SUBSTRING_INDEX(p.sku, '-', 1)                         AS sku_category,
       SUBSTRING_INDEX(SUBSTRING_INDEX(p.sku, '-', 2), '-', -1) AS sku_brand,
       sub.category_code, b.brand_code,
       top.name_en AS top_category, sub.name_en AS sub_category, b.brand_name,
       p.product_name, p.unit_price, p.status
FROM products p
JOIN categories sub ON sub.category_id = p.category_id           -- หมวดย่อย
JOIN categories top ON top.category_id = sub.parent_category_id  -- หมวดหลัก (self join!)
JOIN brands b       ON b.brand_id = p.brand_id
LIMIT 10;

-- ---------------------------------------------------------------------
-- 6.4 Profiling: เข้าใจรูปร่างข้อมูลก่อนเขียน pipeline
-- ---------------------------------------------------------------------
-- ช่วงเวลาและความสดของข้อมูล (freshness)
SELECT MIN(ordered_at) AS first_order, MAX(ordered_at) AS last_order, MAX(updated_at) AS last_change
FROM orders;

-- การกระจายของสถานะ
SELECT status, COUNT(*) AS n, ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM orders GROUP BY status ORDER BY n DESC;

-- NULL มากแค่ไหนในแต่ละคอลัมน์ (บอกว่าคอลัมน์ไหน "ไม่บังคับ" และทำไม)
SELECT COUNT(*)                   AS n_orders,
       SUM(paid_at IS NULL)       AS null_paid_at,
       SUM(shipped_at IS NULL)    AS null_shipped_at,
       SUM(coupon_id IS NULL)     AS null_coupon,
       SUM(cancel_reason IS NULL) AS null_cancel_reason
FROM orders;

-- business key ซ้ำไหม (ควรได้ 0 แถว)
SELECT customer_code, COUNT(*) FROM customers GROUP BY customer_code HAVING COUNT(*) > 1;

-- ---------------------------------------------------------------------
-- 6.5 ชีวิตของ 1 order: ข้อมูลกระจายอยู่ใน 7 ตาราง
-- ---------------------------------------------------------------------
-- เลือก order ที่คืนสินค้า (มีครบทุกขั้นตอน)
SET @oid = (SELECT order_id FROM orders WHERE status = 'returned' AND return_reason IS NOT NULL ORDER BY order_id LIMIT 1);
SELECT @oid;

SELECT order_number, status, payment_method, subtotal_amount, discount_amount, shipping_fee,
       total_amount, ordered_at, paid_at, shipped_at, delivered_at, return_reason
FROM orders WHERE order_id = @oid;

SELECT oi.line_number, p.sku, p.product_name, oi.quantity, oi.unit_price, oi.line_total
FROM order_items oi JOIN products p ON p.product_id = oi.product_id WHERE oi.order_id = @oid;

SELECT from_status, to_status, changed_by, note, changed_at
FROM order_status_history WHERE order_id = @oid ORDER BY history_id;         -- event log (append-only)

SELECT payment_code, attempt_number, payment_method, status, amount, created_at, updated_at
FROM payments WHERE order_id = @oid;

SELECT e.status, e.location, e.description, e.event_at
FROM shipment_tracking_events e JOIN shipments s ON s.shipment_id = e.shipment_id
WHERE s.order_id = @oid ORDER BY e.event_id;

SELECT refund_code, amount, reason, status, requested_at, processed_at FROM refunds WHERE order_id = @oid;

-- 💡 สังเกต 2 แบบของตาราง
--   state table  (orders, payments, shipments): 1 แถว/สิ่งของ ค่าถูก UPDATE ไปเรื่อย ๆ (มี updated_at)
--   event table  (order_status_history, tracking events, inventory_movements): INSERT อย่างเดียว ไม่เคยแก้
--   → สองแบบนี้ต้องใช้วิธีโหลดต่างกัน (บทที่ 8)

-- ---------------------------------------------------------------------
-- 6.6 คำถามธุรกิจแรก ๆ (ใช้ความรู้บทที่ 3-5 ทั้งหมด)
-- ---------------------------------------------------------------------
-- ยอดขายรายเดือน (ไม่นับยกเลิก)
SELECT DATE_FORMAT(ordered_at, '%Y-%m') AS month,
       COUNT(*)                         AS orders,
       SUM(total_amount)                AS gmv,
       ROUND(AVG(total_amount))         AS aov
FROM orders
WHERE status <> 'cancelled'
GROUP BY month
ORDER BY month;

-- ยอดขายตามหมวดหลัก
SELECT top.name_en AS category, SUM(oi.line_total) AS revenue, SUM(oi.quantity) AS units
FROM order_items oi
JOIN orders o       ON o.order_id = oi.order_id AND o.status <> 'cancelled'
JOIN products p     ON p.product_id = oi.product_id
JOIN categories sub ON sub.category_id = p.category_id
JOIN categories top ON top.category_id = sub.parent_category_id
GROUP BY top.name_en
ORDER BY revenue DESC;

-- ออเดอร์ตามภาค (ที่อยู่จัดส่ง → จังหวัด → ภาค)
SELECT pr.region, COUNT(*) AS orders
FROM orders o
JOIN customer_addresses a ON a.address_id = o.shipping_address_id
JOIN provinces pr         ON pr.province_id = a.province_id
WHERE o.ordered_at >= '2026-01-01'
GROUP BY pr.region
ORDER BY orders DESC;

-- สรุปบทที่ 6
--   information_schema (tables, columns, key_column_usage, check_constraints) · profiling
--   business key vs surrogate key · state table vs event table · 1 business event กระจายหลายตาราง
