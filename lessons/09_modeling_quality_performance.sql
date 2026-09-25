-- =====================================================================
--  บทที่ 9: View · SCD Type 2 · Data Quality checks · Index & EXPLAIN
-- =====================================================================
USE lab_student;   -- ⚠️ แก้เป็น database ของตัวเอง
-- ต้องรันบทที่ 8 มาก่อน (ใช้ dim_product, dim_customer, stg_orders)

-- ---------------------------------------------------------------------
-- 9.1 VIEW: query ที่ตั้งชื่อไว้ (ไม่เก็บข้อมูล คำนวณใหม่ทุกครั้งที่ SELECT)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_order_summary AS
SELECT o.order_id, o.order_number, o.ordered_at, o.status, o.total_amount,
       c.customer_code, c.membership_tier
FROM stg_orders o
JOIN dim_customer c ON c.customer_id = o.customer_id;

SELECT membership_tier, COUNT(*) AS orders, SUM(total_amount) AS gmv
FROM v_order_summary
WHERE status = 'completed'
GROUP BY membership_tier;

-- 💡 View vs Table
--   view  = สดเสมอ, ไม่กินพื้นที่, แต่ช้าถ้า query ข้างในหนัก (คำนวณทุกครั้ง)
--   table = ต้องมี pipeline refresh, แต่อ่านเร็ว (บทที่ 8 คือการ "materialize" ผลลัพธ์ลงตาราง)
--   ใช้ view เพื่อซ่อนความซับซ้อน / กำหนดสิทธิ์ให้เห็นเฉพาะบางคอลัมน์

-- ---------------------------------------------------------------------
-- 9.2 SCD Type 2: เก็บ "ประวัติ" ของ dimension ที่เปลี่ยนตามเวลา
-- ---------------------------------------------------------------------
-- ปัญหา: dim_customer (บทที่ 8) เก็บแค่ tier ปัจจุบัน
--        ถ้าถาม "ยอดขายเดือน ม.ค. แยกตาม tier ของลูกค้า ณ ตอนนั้น" จะตอบผิด
-- SCD Type 1 = เขียนทับ (ไม่มีประวัติ) · SCD Type 2 = ปิดแถวเก่า + เปิดแถวใหม่
-- เริ่มจากข้อมูลของเล่น 4 คนให้เห็นภาพก่อน
DROP TABLE IF EXISTS src_member;
CREATE TABLE src_member (                          -- จำลองตาราง source ที่ถูกเขียนทับเสมอ
    member_code  VARCHAR(12) NOT NULL PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    tier         VARCHAR(10) NOT NULL,
    province     VARCHAR(50) NOT NULL
);
INSERT INTO src_member VALUES
 ('MEM-0001', 'สมชาย', 'bronze', 'กรุงเทพมหานคร'),
 ('MEM-0002', 'สมหญิง', 'silver', 'เชียงใหม่'),
 ('MEM-0003', 'วิชัย',  'bronze', 'ขอนแก่น'),
 ('MEM-0004', 'นภา',   'gold',   'ภูเก็ต');

DROP TABLE IF EXISTS dim_member_scd2;
CREATE TABLE dim_member_scd2 (
    member_sk    INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,   -- surrogate key (1 แถว = 1 เวอร์ชัน)
    member_code  VARCHAR(12)  NOT NULL,                              -- natural key (ซ้ำได้ ข้ามเวอร์ชัน)
    name         VARCHAR(100) NOT NULL,
    tier         VARCHAR(10)  NOT NULL,
    province     VARCHAR(50)  NOT NULL,
    valid_from   DATETIME     NOT NULL,
    valid_to     DATETIME     NULL,                                  -- NULL = ยังใช้อยู่
    is_current   BOOLEAN      NOT NULL,
    INDEX ix_scd_code (member_code, is_current)
);

-- ===== บล็อก SCD2 LOAD (รันทุกครั้งที่ต้องการ sync) ===============================
SET @load_time = '2026-01-01 00:00:00';          -- เวลาของรอบนี้ (ปกติ = NOW() หรือเวลาของ batch)

START TRANSACTION;
-- ขั้น 1: ปิดเวอร์ชันปัจจุบันของสมาชิกที่ "ค่าเปลี่ยน"
UPDATE dim_member_scd2 d
JOIN src_member s ON s.member_code = d.member_code
SET d.valid_to = @load_time, d.is_current = FALSE
WHERE d.is_current = TRUE
  AND (d.tier <> s.tier OR d.province <> s.province OR d.name <> s.name);

-- ขั้น 2: เปิดเวอร์ชันใหม่ ให้สมาชิกที่ "ไม่มีเวอร์ชันปัจจุบัน" (สมาชิกใหม่ + ที่เพิ่งถูกปิดในขั้น 1)
INSERT INTO dim_member_scd2 (member_code, name, tier, province, valid_from, valid_to, is_current)
SELECT s.member_code, s.name, s.tier, s.province, @load_time, NULL, TRUE
FROM src_member s
LEFT JOIN dim_member_scd2 d ON d.member_code = s.member_code AND d.is_current = TRUE
WHERE d.member_sk IS NULL;
COMMIT;
-- ================================================================================
SELECT * FROM dim_member_scd2 ORDER BY member_code, valid_from;     -- รอบแรก: 4 แถว

-- 📅 เวลาผ่านไป: source เปลี่ยน (ถูกเขียนทับ ไม่มีประวัติในตัว source เอง)
UPDATE src_member SET tier = 'silver' WHERE member_code = 'MEM-0001';        -- อัปเกรด
UPDATE src_member SET province = 'ชลบุรี' WHERE member_code = 'MEM-0003';    -- ย้ายบ้าน
INSERT INTO src_member VALUES ('MEM-0005', 'ธนพล', 'bronze', 'ระยอง');       -- สมาชิกใหม่

-- 👉 ตั้ง @load_time = '2026-03-01 00:00:00' แล้วรัน "บล็อก SCD2 LOAD" อีกครั้ง
SET @load_time = '2026-03-01 00:00:00';
START TRANSACTION;
UPDATE dim_member_scd2 d
JOIN src_member s ON s.member_code = d.member_code
SET d.valid_to = @load_time, d.is_current = FALSE
WHERE d.is_current = TRUE
  AND (d.tier <> s.tier OR d.province <> s.province OR d.name <> s.name);
INSERT INTO dim_member_scd2 (member_code, name, tier, province, valid_from, valid_to, is_current)
SELECT s.member_code, s.name, s.tier, s.province, @load_time, NULL, TRUE
FROM src_member s
LEFT JOIN dim_member_scd2 d ON d.member_code = s.member_code AND d.is_current = TRUE
WHERE d.member_sk IS NULL;
COMMIT;

SELECT * FROM dim_member_scd2 ORDER BY member_code, valid_from;     -- 7 แถว: ประวัติครบ
-- ✅ รันบล็อกซ้ำโดยไม่มีอะไรเปลี่ยน → ไม่มีแถวเพิ่ม (idempotent)

-- Point-in-time query: "tier ของแต่ละคน ณ วันที่ 15 ก.พ. 2026"
SET @as_of = '2026-02-15';
SELECT member_code, tier, province
FROM dim_member_scd2
WHERE valid_from <= @as_of AND (valid_to IS NULL OR valid_to > @as_of);

-- 💡 ของจริงใน ecommerce: product_price_history คือ SCD2 ของราคาสินค้า
SELECT product_id, unit_price, change_reason, valid_from, valid_to, is_current
FROM ecommerce.product_price_history
WHERE product_id = (SELECT product_id FROM ecommerce.product_price_history
                    GROUP BY product_id ORDER BY COUNT(*) DESC LIMIT 1)
ORDER BY valid_from;

-- ---------------------------------------------------------------------
-- 9.3 Data Quality checks: ทุก check = query ที่คืน "จำนวนแถวที่ผิด" (0 = ผ่าน)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS dq_results;
CREATE TABLE dq_results (
    run_at      DATETIME(6)  NOT NULL,
    check_name  VARCHAR(100) NOT NULL,
    violations  BIGINT       NOT NULL,
    passed      BOOLEAN      NOT NULL,
    PRIMARY KEY (run_at, check_name)
);

SET @run_at = NOW(6);
INSERT INTO dq_results (run_at, check_name, violations, passed)
SELECT @run_at, check_name, violations, violations = 0
FROM (
    -- 1) Completeness: จำนวนแถวตรงกับ source (ถึง watermark ที่โหลด)
    SELECT 'row_count_matches_source' AS check_name,
           ABS((SELECT COUNT(*) FROM ecommerce.orders WHERE updated_at <= (SELECT watermark_value FROM etl_watermark WHERE table_name = 'orders'))
             - (SELECT COUNT(*) FROM stg_orders)) AS violations
    UNION ALL
    -- 2) Accuracy: ยอดเงินรวมตรงกับ source
    SELECT 'total_amount_matches_source',
           ABS((SELECT SUM(total_amount) FROM ecommerce.orders WHERE updated_at <= (SELECT watermark_value FROM etl_watermark WHERE table_name = 'orders'))
             - (SELECT SUM(total_amount) FROM stg_orders)) <> 0
    UNION ALL
    -- 3) Uniqueness: business key ไม่ซ้ำ
    SELECT 'order_number_unique', COUNT(*) - COUNT(DISTINCT order_number) FROM stg_orders
    UNION ALL
    -- 4) Not null
    SELECT 'customer_id_not_null', SUM(customer_id IS NULL) FROM stg_orders
    UNION ALL
    -- 5) Referential integrity: order ต้องมีลูกค้าใน dim_customer (orphan)
    SELECT 'orders_have_customer', COUNT(*) FROM stg_orders o
    LEFT JOIN dim_customer c ON c.customer_id = o.customer_id WHERE c.customer_id IS NULL
    UNION ALL
    -- 6) Validity: ค่าอยู่ในชุดที่อนุญาต
    SELECT 'status_accepted_values', SUM(status NOT IN ('pending_payment','confirmed','processing','shipped','delivered',
                                                        'completed','cancelled','delivery_failed','return_requested','returned'))
    FROM stg_orders
    UNION ALL
    -- 7) Freshness: ข้อมูลล่าสุดไม่เก่ากว่า 2 วัน (เทียบกับ source)
    SELECT 'fresh_within_2_days',
           TIMESTAMPDIFF(HOUR, (SELECT MAX(src_updated_at) FROM stg_orders), (SELECT MAX(updated_at) FROM ecommerce.orders)) > 48
) checks;

SELECT check_name, violations, IF(passed, '✅ pass', '❌ FAIL') AS result FROM dq_results WHERE run_at = @run_at;
-- 💡 ใน pipeline จริง: ถ้ามี check ไม่ผ่าน → หยุด task / แจ้งเตือน ไม่ปล่อยข้อมูลเสียไปถึง dashboard
--    ecommerce มีชุด check แบบเดียวกันนี้ 38 ข้อ (validate_data.py) ลองเปิดดูเป็นตัวอย่าง

-- ---------------------------------------------------------------------
-- 9.4 Index & EXPLAIN: ทำไม query ช้า
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS perf_orders;
CREATE TABLE perf_orders AS                         -- CTAS = ไม่มี index ใด ๆ
SELECT order_id, customer_id, status, ordered_at, total_amount FROM ecommerce.orders;

SET @cid = (SELECT customer_id FROM perf_orders ORDER BY order_id DESC LIMIT 1);

EXPLAIN SELECT * FROM perf_orders WHERE customer_id = @cid;
-- 👀 type = ALL (อ่านทั้งตาราง), rows ≈ ทั้งตาราง

EXPLAIN ANALYZE SELECT * FROM perf_orders WHERE customer_id = @cid;   -- เวลาจริง (actual time)

CREATE INDEX ix_perf_customer ON perf_orders (customer_id);

EXPLAIN SELECT * FROM perf_orders WHERE customer_id = @cid;
-- 👀 type = ref, key = ix_perf_customer, rows = ไม่กี่แถว
EXPLAIN ANALYZE SELECT * FROM perf_orders WHERE customer_id = @cid;

-- Composite index: ลำดับคอลัมน์สำคัญ (เท่ากัน = ก่อน, ช่วง = หลัง)
CREATE INDEX ix_perf_status_date ON perf_orders (status, ordered_at);
EXPLAIN SELECT COUNT(*) FROM perf_orders WHERE status = 'completed' AND ordered_at >= '2026-09-01';

-- ⚠️ ห่อคอลัมน์ด้วยฟังก์ชัน = ใช้ index ไม่ได้
EXPLAIN SELECT COUNT(*) FROM perf_orders WHERE status = 'completed' AND DATE(ordered_at) = '2026-09-01';          -- ใช้ได้แค่ส่วน status
EXPLAIN SELECT COUNT(*) FROM perf_orders WHERE status = 'completed'
                                          AND ordered_at >= '2026-09-01' AND ordered_at < '2026-09-02';           -- ✅ ใช้ได้ทั้งคู่

-- 💡 index เร่งการอ่าน แต่ทำให้ INSERT/UPDATE ช้าลงและกินพื้นที่
--    ตาราง staging ที่โหลดหนัก ๆ: สร้าง index หลังโหลดเสร็จ หรือมีเฉพาะที่จำเป็น (PK + คอลัมน์ watermark)
DROP TABLE perf_orders;

-- สรุปบทที่ 9
--   VIEW · SCD Type 2 (ปิดแถวเก่า + เปิดแถวใหม่, point-in-time query)
--   DQ checks: completeness / accuracy / uniqueness / not null / referential / validity / freshness
--   EXPLAIN / EXPLAIN ANALYZE · index เดี่ยว / composite · อย่าห่อคอลัมน์ด้วยฟังก์ชัน
--   ➡️ ทำ Assignment A5
