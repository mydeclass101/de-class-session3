-- =====================================================================
--  บทที่ 8: รูปแบบการโหลดข้อมูลของ Data Engineer (DDL + DML ในงาน pipeline)
--  อ่านจาก ecommerce (source) → เขียนลง lab_ ของตัวเอง (target / warehouse)
--
--   8.1 CTAS vs explicit DDL              8.5 Incremental load ด้วย watermark ⭐
--   8.2 Full reload แบบ atomic swap        8.6 Event table: incremental ด้วย id
--   8.3 Idempotent partition reload       8.7 Dedup ข้อมูลดิบที่มาซ้ำ
--   8.4 UPSERT (INSERT ... ON DUPLICATE KEY UPDATE)
-- =====================================================================
USE lab_student;   -- ⚠️ แก้เป็น database ของตัวเอง

-- 💡 คุณสมบัติที่ต้องการจาก pipeline ทุกตัว
--    Idempotent  = รันซ้ำกี่รอบ ผลลัพธ์เหมือนรันรอบเดียว (ไม่ซ้ำ ไม่หาย)
--    Atomic      = สำเร็จทั้งก้อนหรือไม่เปลี่ยนเลย (คนใช้ข้อมูลไม่เห็นสถานะครึ่ง ๆ)
--    Incremental = โหลดเฉพาะส่วนที่เปลี่ยน เมื่อข้อมูลใหญ่เกินกว่าจะโหลดใหม่ทั้งหมดทุกครั้ง

-- ---------------------------------------------------------------------
-- 8.1 CTAS (CREATE TABLE ... AS SELECT) vs explicit DDL
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS stg_products_ctas;
CREATE TABLE stg_products_ctas AS
SELECT product_id, sku, product_name, unit_price, status
FROM ecommerce.products;

SHOW CREATE TABLE stg_products_ctas;    -- 👀 ไม่มี PRIMARY KEY / index / constraint ติดมาด้วย!
DROP TABLE stg_products_ctas;
-- CTAS เร็วและง่าย (เหมาะกับงานสำรวจ/ตารางชั่วคราว) แต่ตารางถาวรควร "ออกแบบ DDL เอง" แล้ว INSERT ... SELECT

-- dim_product: denormalize สินค้า + หมวด + แบรนด์ ไว้ในตารางเดียว (analyst ใช้ง่าย ไม่ต้อง join 4 ตาราง)
DROP TABLE IF EXISTS dim_product;
CREATE TABLE dim_product (
    product_id    INT           NOT NULL PRIMARY KEY,
    sku           VARCHAR(20)   NOT NULL UNIQUE,
    product_name  VARCHAR(255)  NOT NULL,
    top_category  VARCHAR(100)  NOT NULL,
    sub_category  VARCHAR(100)  NOT NULL,
    brand_name    VARCHAR(100)  NOT NULL,
    unit_price    DECIMAL(12,2) NOT NULL,
    status        VARCHAR(15)   NOT NULL,
    loaded_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- 8.2 Full reload + atomic swap (ตารางเล็ก/กลาง: โหลดใหม่หมดทุกรอบ ง่ายและถูกต้องเสมอ)
-- ---------------------------------------------------------------------
-- ปัญหาของ TRUNCATE + INSERT: ระหว่างโหลด คนที่ query จะเห็นตารางว่าง/ไม่ครบ
-- ทางแก้: โหลดลงตารางใหม่ให้เสร็จก่อน แล้ว "สลับชื่อ" ในคำสั่งเดียว (RENAME TABLE หลายคู่ = atomic)
DROP TABLE IF EXISTS dim_product_new;
CREATE TABLE dim_product_new LIKE dim_product;

INSERT INTO dim_product_new (product_id, sku, product_name, top_category, sub_category, brand_name, unit_price, status)
SELECT p.product_id, p.sku, p.product_name, top.name_en, sub.name_en, b.brand_name, p.unit_price, p.status
FROM ecommerce.products p
JOIN ecommerce.categories sub ON sub.category_id = p.category_id
JOIN ecommerce.categories top ON top.category_id = sub.parent_category_id
JOIN ecommerce.brands b       ON b.brand_id = p.brand_id;

RENAME TABLE dim_product TO dim_product_old, dim_product_new TO dim_product;
DROP TABLE dim_product_old;

SELECT COUNT(*) AS n_products, COUNT(DISTINCT top_category) AS n_categories FROM dim_product;
-- ✅ รันบล็อก 8.2 ซ้ำกี่ครั้งก็ได้ผลเหมือนเดิม = idempotent

-- ---------------------------------------------------------------------
-- 8.3 Idempotent partition reload: "ลบช่วงที่จะโหลด แล้วใส่ใหม่" ในทรานแซกชันเดียว
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS fct_daily_sales;
CREATE TABLE fct_daily_sales (
    sales_date    DATE          NOT NULL,
    top_category  VARCHAR(100)  NOT NULL,
    orders        INT           NOT NULL,
    units         INT           NOT NULL,
    revenue       DECIMAL(14,2) NOT NULL,
    loaded_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (sales_date, top_category)
);

-- พารามิเตอร์ของรอบนี้ (ใน Airflow จะมาจาก data interval ของ DAG run)
SET @from = '2026-09-01', @to = '2026-09-07';

START TRANSACTION;
DELETE FROM fct_daily_sales WHERE sales_date BETWEEN @from AND @to;
INSERT INTO fct_daily_sales (sales_date, top_category, orders, units, revenue)
SELECT DATE(o.ordered_at), d.top_category, COUNT(DISTINCT o.order_id), SUM(oi.quantity), SUM(oi.line_total)
FROM ecommerce.orders o
JOIN ecommerce.order_items oi ON oi.order_id = o.order_id
JOIN dim_product d            ON d.product_id = oi.product_id
WHERE o.status <> 'cancelled'
  AND o.ordered_at >= @from AND o.ordered_at < @to + INTERVAL 1 DAY      -- ✅ range บนคอลัมน์ตรง ๆ (ใช้ index ได้)
GROUP BY DATE(o.ordered_at), d.top_category;
COMMIT;

SELECT sales_date, COUNT(*) AS n_categories, SUM(revenue) AS revenue
FROM fct_daily_sales GROUP BY sales_date ORDER BY sales_date;
-- ✅ รันบล็อก START…COMMIT ซ้ำ: จำนวนแถวไม่เพิ่ม · เปลี่ยน @from/@to เพื่อโหลดช่วงอื่น (= backfill)
-- ⚠️ INSERT เฉย ๆ รอบสองจะ error duplicate key (หรือแย่กว่า: ข้อมูลซ้ำเงียบ ๆ ถ้าไม่มี PK)

-- ---------------------------------------------------------------------
-- 8.4 UPSERT: มีแล้ว → UPDATE, ยังไม่มี → INSERT
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS dim_customer;
CREATE TABLE dim_customer (
    customer_id      BIGINT       NOT NULL PRIMARY KEY,
    customer_code    VARCHAR(12)  NOT NULL UNIQUE,
    full_name        VARCHAR(200) NOT NULL,
    membership_tier  VARCHAR(10)  NOT NULL,
    status           VARCHAR(10)  NOT NULL,
    registered_at    DATETIME     NOT NULL,
    src_updated_at   DATETIME     NOT NULL,          -- updated_at ของ source (ใช้ตรวจความสด/เปรียบเทียบ)
    loaded_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- รูปแบบ: INSERT INTO target (...) SELECT ... FROM (<source query>) AS src ON DUPLICATE KEY UPDATE col = src.col
INSERT INTO dim_customer (customer_id, customer_code, full_name, membership_tier, status, registered_at, src_updated_at)
SELECT * FROM (
    SELECT customer_id, customer_code, CONCAT(first_name, ' ', last_name) AS full_name,
           membership_tier, status, registered_at, updated_at AS src_updated_at
    FROM ecommerce.customers
) AS src
ON DUPLICATE KEY UPDATE
    full_name       = src.full_name,
    membership_tier = src.membership_tier,
    status          = src.status,
    src_updated_at  = src.src_updated_at;

SELECT COUNT(*) AS n_customers FROM dim_customer;
-- ✅ รันซ้ำได้: แถวเดิมถูก update ไม่เกิดแถวซ้ำ
-- 💡 affected rows ของ upsert: 1 = insert ใหม่, 2 = update, 0 = ไม่มีอะไรเปลี่ยน

-- ---------------------------------------------------------------------
-- 8.5 ⭐ Incremental load ด้วย watermark (updated_at)
-- ---------------------------------------------------------------------
-- แนวคิด: จำไว้ว่าโหลดถึง updated_at ไหนแล้ว รอบหน้าดึงเฉพาะแถวที่ updated_at ใหม่กว่านั้น
--         + upsert ลงปลายทาง → ได้ทั้งแถวใหม่ (INSERT) และแถวเดิมที่สถานะเปลี่ยน (UPDATE)
DROP TABLE IF EXISTS etl_watermark;
CREATE TABLE etl_watermark (
    table_name   VARCHAR(64) NOT NULL PRIMARY KEY,
    watermark_value   DATETIME    NOT NULL,
    updated_at   DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
INSERT INTO etl_watermark (table_name, watermark_value) VALUES ('orders', '1970-01-01');   -- ยังไม่เคยโหลด

DROP TABLE IF EXISTS etl_load_log;
CREATE TABLE etl_load_log (
    load_id       INT         NOT NULL AUTO_INCREMENT PRIMARY KEY,
    table_name    VARCHAR(64) NOT NULL,
    wm_from       DATETIME    NOT NULL,
    wm_to         DATETIME    NOT NULL,
    rows_new      INT         NOT NULL,
    rows_changed  INT         NOT NULL,
    loaded_at     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS stg_orders;
CREATE TABLE stg_orders (
    order_id        BIGINT        NOT NULL PRIMARY KEY,
    order_number    VARCHAR(20)   NOT NULL,
    customer_id     BIGINT        NOT NULL,
    status          VARCHAR(20)   NOT NULL,
    payment_method  VARCHAR(20)   NOT NULL,
    total_amount    DECIMAL(12,2) NOT NULL,
    ordered_at      DATETIME      NOT NULL,
    src_updated_at  DATETIME      NOT NULL,
    loaded_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX ix_stg_orders_updated (src_updated_at)
);

-- ===== บล็อก LOAD (รันทั้งบล็อกทุกครั้งที่ต้องการ sync) ===========================
SET @wm_from = (SELECT watermark_value FROM etl_watermark WHERE table_name = 'orders');
SET @wm_to   = (SELECT MAX(updated_at) FROM ecommerce.orders);          -- ขอบบนของรอบนี้ (ล็อกไว้ก่อนเริ่ม)

START TRANSACTION;
INSERT INTO etl_load_log (table_name, wm_from, wm_to, rows_new, rows_changed)
SELECT 'orders', @wm_from, @wm_to,
       COALESCE(SUM(s.order_id IS NULL), 0), COALESCE(SUM(s.order_id IS NOT NULL), 0)
FROM ecommerce.orders o
LEFT JOIN stg_orders s ON s.order_id = o.order_id
WHERE o.updated_at > @wm_from AND o.updated_at <= @wm_to;

INSERT INTO stg_orders (order_id, order_number, customer_id, status, payment_method, total_amount, ordered_at, src_updated_at)
SELECT * FROM (
    SELECT order_id, order_number, customer_id, status, payment_method, total_amount, ordered_at, updated_at AS src_updated_at
    FROM ecommerce.orders
    WHERE updated_at > @wm_from AND updated_at <= @wm_to
) AS src
ON DUPLICATE KEY UPDATE
    status         = src.status,
    payment_method = src.payment_method,
    total_amount   = src.total_amount,
    src_updated_at = src.src_updated_at;

UPDATE etl_watermark SET watermark_value = @wm_to WHERE table_name = 'orders';
COMMIT;
-- ================================================================================

SELECT * FROM etl_load_log ORDER BY load_id;      -- รอบแรก = โหลดทั้งหมด (initial / full load)
SELECT COUNT(*) AS n_stg, (SELECT COUNT(*) FROM ecommerce.orders) AS n_src FROM stg_orders;

-- 🧪 ทดลอง: ทำให้ข้อมูลต้นทางเดินหน้า 1 step (order ใหม่ + สถานะ order เก่าเปลี่ยน) โดยรันใน terminal
--      docker compose exec mysql sh /scripts/advance.sh
--    แล้วรัน "บล็อก LOAD" อีกครั้ง → etl_load_log จะมี rows_new (order ใหม่) และ rows_changed (order เก่าที่สถานะเปลี่ยน)
--    รันบล็อก LOAD ซ้ำทันทีอีกรอบ → 0 / 0 (ไม่มีอะไรเปลี่ยน = idempotent)

-- ดูว่าสถานะ order เปลี่ยนไปอย่างไรในรอบล่าสุด
SELECT status, COUNT(*) AS n
FROM stg_orders
WHERE src_updated_at > (SELECT wm_from FROM etl_load_log ORDER BY load_id DESC LIMIT 1)
GROUP BY status ORDER BY n DESC;

-- ⚠️ ข้อควรระวังของ watermark
--   1) ใช้ขอบบน @wm_to ที่ "ล็อก" ไว้ก่อนเริ่ม ไม่ใช่ NOW() → แถวที่เข้ามาระหว่างโหลดจะไปอยู่รอบหน้า ไม่หล่น
--   2) แถวที่ commit ช้า (updated_at เก่ากว่า watermark) จะหลุด → ถอย watermark ย้อน (lookback) สักพัก
--      เช่น WHERE updated_at > @wm_from - INTERVAL 1 HOUR ได้อย่างปลอดภัย เพราะ upsert รันซ้ำได้
--   3) การ "ลบแถว" ใน source มองไม่เห็นจาก updated_at → ต้องใช้ soft delete หรือ CDC (binlog)

-- ---------------------------------------------------------------------
-- 8.6 Event table (append-only): incremental ด้วย id ที่เพิ่มขึ้นเรื่อย ๆ
-- ---------------------------------------------------------------------
-- order_status_history ไม่มีการ UPDATE → ดึงแค่ id ที่มากกว่าที่เคยโหลด แล้ว INSERT ธรรมดา
DROP TABLE IF EXISTS stg_order_events;
CREATE TABLE stg_order_events (
    history_id   BIGINT      NOT NULL PRIMARY KEY,
    order_id     BIGINT      NOT NULL,
    from_status  VARCHAR(20) NULL,
    to_status    VARCHAR(20) NOT NULL,
    changed_at   DATETIME    NOT NULL
);

SET @last_id = (SELECT COALESCE(MAX(history_id), 0) FROM stg_order_events);   -- watermark = ค่าสูงสุดในปลายทาง
INSERT INTO stg_order_events (history_id, order_id, from_status, to_status, changed_at)
SELECT history_id, order_id, from_status, to_status, changed_at
FROM ecommerce.order_status_history
WHERE history_id > @last_id AND changed_at >= '2026-09-01';   -- (จำกัดช่วงเพื่อให้ demo เร็ว)

SELECT to_status, COUNT(*) AS n FROM stg_order_events GROUP BY to_status ORDER BY n DESC;

-- ---------------------------------------------------------------------
-- 8.7 Dedup: ข้อมูลดิบ (landing) ที่มาซ้ำ / มาหลายเวอร์ชัน
-- ---------------------------------------------------------------------
-- สถานการณ์: API ส่งข้อมูลซ้ำ (retry) และส่ง order เดิมมาหลายเวอร์ชันเมื่อสถานะเปลี่ยน
DROP TABLE IF EXISTS raw_orders_landing;
CREATE TABLE raw_orders_landing (
    ingest_id     BIGINT      NOT NULL AUTO_INCREMENT PRIMARY KEY,
    order_id      BIGINT      NOT NULL,
    status        VARCHAR(20) NOT NULL,
    updated_at    DATETIME    NOT NULL,
    ingested_at   DATETIME    NOT NULL
);
-- จำลอง: order 3 รายการ, ส่งซ้ำ + มีเวอร์ชันใหม่
INSERT INTO raw_orders_landing (order_id, status, updated_at, ingested_at) VALUES
 (1001, 'pending_payment', '2026-09-20 10:00', '2026-09-20 10:05'),
 (1001, 'pending_payment', '2026-09-20 10:00', '2026-09-20 10:06'),   -- ซ้ำเป๊ะ (retry)
 (1001, 'confirmed',       '2026-09-20 10:03', '2026-09-20 11:00'),   -- เวอร์ชันใหม่
 (1002, 'confirmed',       '2026-09-20 12:00', '2026-09-20 12:01'),
 (1003, 'shipped',         '2026-09-21 09:00', '2026-09-21 09:30'),
 (1003, 'delivered',       '2026-09-22 14:00', '2026-09-22 14:10'),
 (1003, 'shipped',         '2026-09-21 09:00', '2026-09-22 15:00');   -- ⚠️ เวอร์ชันเก่ามาถึงทีหลัง (out-of-order)

-- เก็บ "เวอร์ชันล่าสุดตามเวลาของ source" ต่อ order
SELECT order_id, status, updated_at
FROM (
    SELECT r.*,
           ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY updated_at DESC, ingested_at DESC) AS rn
    FROM raw_orders_landing r
) x
WHERE rn = 1
ORDER BY order_id;
-- ✅ 1003 = delivered (ถ้าเรียงตาม ingested_at จะได้ shipped ซึ่งผิด!)
-- 💡 เลือกคีย์เรียงให้ถูก: ใช้เวลาของ source (updated_at) ก่อน แล้วค่อยใช้เวลาที่รับเข้ามาตัดสินเมื่อเท่ากัน

-- สรุปบทที่ 8
--   CTAS vs DDL เอง · full reload + atomic RENAME swap · DELETE+INSERT ตามช่วง (idempotent, backfill ได้)
--   UPSERT · incremental ด้วย watermark (updated_at) + log · incremental ด้วย id (event table) · dedup ด้วย ROW_NUMBER
