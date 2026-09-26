-- =====================================================================
--  บทที่ 4: Aggregation: สรุปข้อมูล
--  COUNT · SUM · AVG · MIN · MAX · GROUP BY · HAVING · conditional aggregation
--  ข้อมูล: ยอดขายร้านกาแฟ 3 สาขา 1 สัปดาห์ (24 แถว)
-- =====================================================================
USE lab_student;   -- ⚠️ แก้เป็น database ของตัวเอง

DROP TABLE IF EXISTS sales;
CREATE TABLE sales (
    sale_id      INT           NOT NULL PRIMARY KEY,
    sold_at      DATETIME      NOT NULL,
    branch       VARCHAR(20)   NOT NULL,
    sku          VARCHAR(20)   NOT NULL,
    category     VARCHAR(20)   NOT NULL,
    qty          INT           NOT NULL,
    unit_price   DECIMAL(8,2)  NOT NULL,
    payment      VARCHAR(10)   NOT NULL,
    member_code  VARCHAR(12)   NULL           -- NULL = ลูกค้าที่ไม่ใช่สมาชิก
);
INSERT INTO sales VALUES
 ( 1, '2026-09-07 07:45', 'สยาม',   'COF-AME-002', 'coffee', 2,  60, 'promptpay', 'MEM-0001'),
 ( 2, '2026-09-07 08:10', 'สยาม',   'BAK-CRO-001', 'bakery', 1,  65, 'card',      NULL),
 ( 3, '2026-09-07 12:30', 'อารีย์',  'COF-LAT-003', 'coffee', 1,  70, 'cash',      'MEM-0002'),
 ( 4, '2026-09-07 15:05', 'ทองหล่อ', 'TEA-MAT-002', 'tea',    2,  80, 'card',      'MEM-0004'),
 ( 5, '2026-09-08 07:55', 'สยาม',   'COF-ESP-001', 'coffee', 1,  55, 'cash',      NULL),
 ( 6, '2026-09-08 09:20', 'อารีย์',  'TEA-THA-001', 'tea',    3,  55, 'promptpay', 'MEM-0003'),
 ( 7, '2026-09-08 13:40', 'ทองหล่อ', 'BAK-CHC-003', 'bakery', 1,  95, 'card',      'MEM-0004'),
 ( 8, '2026-09-08 16:15', 'สยาม',   'COF-MOC-004', 'coffee', 2,  75, 'promptpay', NULL),
 ( 9, '2026-09-09 08:05', 'อารีย์',  'COF-AME-002', 'coffee', 1,  60, 'cash',      'MEM-0002'),
 (10, '2026-09-09 11:50', 'สยาม',   'MER-TUM-001', 'merch',  1, 490, 'card',      'MEM-0001'),
 (11, '2026-09-09 14:30', 'ทองหล่อ', 'COF-LAT-003', 'coffee', 2,  70, 'promptpay', NULL),
 (12, '2026-09-10 07:30', 'สยาม',   'COF-AME-002', 'coffee', 3,  60, 'promptpay', 'MEM-0005'),
 (13, '2026-09-10 10:10', 'อารีย์',  'BAK-BRW-002', 'bakery', 2,  59, 'cash',      NULL),
 (14, '2026-09-10 17:45', 'ทองหล่อ', 'TEA-MAT-002', 'tea',    1,  80, 'card',      NULL),
 (15, '2026-09-11 08:40', 'สยาม',   'COF-LAT-003', 'coffee', 1,  70, 'card',      'MEM-0001'),
 (16, '2026-09-11 12:15', 'อารีย์',  'TEA-THA-001', 'tea',    2,  55, 'promptpay', NULL),
 (17, '2026-09-12 09:00', 'ทองหล่อ', 'COF-COC-005', 'coffee', 2,  95, 'card',      'MEM-0004'),
 (18, '2026-09-12 10:30', 'สยาม',   'BAK-CRO-001', 'bakery', 2,  65, 'promptpay', NULL),
 (19, '2026-09-12 14:00', 'อารีย์',  'COF-MOC-004', 'coffee', 1,  75, 'cash',      'MEM-0003'),
 (20, '2026-09-13 09:15', 'สยาม',   'COF-AME-002', 'coffee', 4,  60, 'promptpay', NULL),
 (21, '2026-09-13 11:00', 'ทองหล่อ', 'BAK-CHC-003', 'bakery', 2,  95, 'card',      'MEM-0004'),
 (22, '2026-09-13 13:20', 'อารีย์',  'COF-LAT-003', 'coffee', 2,  70, 'promptpay', 'MEM-0002'),
 (23, '2026-09-13 15:45', 'ทองหล่อ', 'MER-TUM-001', 'merch',  1, 490, 'card',      NULL),
 (24, '2026-09-13 16:30', 'สยาม',   'TEA-MAT-002', 'tea',    1,  80, 'cash',      NULL);

SELECT * FROM sales;

-- ---------------------------------------------------------------------
-- 4.1 Aggregate ทั้งตาราง (ได้ 1 แถว)
-- ---------------------------------------------------------------------
SELECT COUNT(*)                   AS n_rows,          -- นับแถว
       COUNT(member_code)         AS n_member_sales,  -- นับเฉพาะที่ไม่ใช่ NULL!
       COUNT(DISTINCT member_code) AS n_members,      -- นับค่าไม่ซ้ำ
       SUM(qty)                   AS units,
       SUM(qty * unit_price)      AS revenue,
       AVG(qty * unit_price)      AS avg_ticket,
       MIN(sold_at)               AS first_sale,
       MAX(sold_at)               AS last_sale
FROM sales;

-- ---------------------------------------------------------------------
-- 4.2 GROUP BY: สรุปแยกกลุ่ม (1 กลุ่ม = 1 แถว)
-- ---------------------------------------------------------------------
SELECT branch,
       COUNT(*)             AS n_bills,
       SUM(qty * unit_price) AS revenue
FROM sales
GROUP BY branch
ORDER BY revenue DESC;

-- หลายคอลัมน์
SELECT branch, category, SUM(qty) AS units
FROM sales
GROUP BY branch, category
ORDER BY branch, units DESC;

-- group ตามค่าที่คำนวณ (วัน / ชั่วโมง)
SELECT DATE(sold_at) AS sale_date, COUNT(*) AS n_bills, SUM(qty * unit_price) AS revenue
FROM sales
GROUP BY DATE(sold_at)
ORDER BY sale_date;

SELECT CASE WHEN HOUR(sold_at) < 11 THEN '1) เช้า' WHEN HOUR(sold_at) < 14 THEN '2) กลางวัน' ELSE '3) บ่าย' END AS daypart,
       COUNT(*) AS n_bills
FROM sales
GROUP BY daypart
ORDER BY daypart;

-- ⚠️ ทุกคอลัมน์ใน SELECT ต้องอยู่ใน GROUP BY หรืออยู่ใน aggregate function
-- ❌ SELECT branch, sku, SUM(qty) FROM sales GROUP BY branch;    -- sku มีหลายค่าต่อสาขา จะเอาค่าไหน? → error (ONLY_FULL_GROUP_BY)

-- ---------------------------------------------------------------------
-- 4.3 WHERE vs HAVING
-- ---------------------------------------------------------------------
--   WHERE  = กรอง "แถว" ก่อนรวมกลุ่ม
--   HAVING = กรอง "กลุ่ม" หลังรวมแล้ว (ใช้ aggregate ได้)
SELECT sku, SUM(qty) AS units
FROM sales
WHERE category = 'coffee'          -- เอาเฉพาะกาแฟก่อน
GROUP BY sku
HAVING SUM(qty) >= 5               -- แล้วเอาเฉพาะ sku ที่ขายรวม >= 5 แก้ว
ORDER BY units DESC;

-- 💡 ลำดับการทำงานจริงของ SQL (ไม่ใช่ลำดับที่เขียน)
--    FROM → WHERE → GROUP BY → HAVING → SELECT → DISTINCT → ORDER BY → LIMIT
--    เลยใช้ alias จาก SELECT ใน WHERE ไม่ได้ แต่ใช้ใน ORDER BY ได้

-- ---------------------------------------------------------------------
-- 4.4 Conditional aggregation: pivot แบบง่าย (ใช้บ่อยมากในรายงาน)
-- ---------------------------------------------------------------------
SELECT branch,
       SUM(CASE WHEN payment = 'cash'      THEN qty * unit_price ELSE 0 END) AS cash,
       SUM(CASE WHEN payment = 'card'      THEN qty * unit_price ELSE 0 END) AS card,
       SUM(CASE WHEN payment = 'promptpay' THEN qty * unit_price ELSE 0 END) AS promptpay,
       ROUND(100 * AVG(member_code IS NOT NULL), 1)                          AS member_pct
FROM sales
GROUP BY branch;

-- ---------------------------------------------------------------------
-- 4.5 💡 DE use case: สร้าง "ตารางสรุป" จากผล aggregate (preview บทที่ 8)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS daily_branch_sales;
CREATE TABLE daily_branch_sales (
    sale_date DATE          NOT NULL,
    branch    VARCHAR(20)   NOT NULL,
    n_bills   INT           NOT NULL,
    revenue   DECIMAL(12,2) NOT NULL,
    PRIMARY KEY (sale_date, branch)                  -- composite key: 1 แถวต่อวันต่อสาขา
);
INSERT INTO daily_branch_sales (sale_date, branch, n_bills, revenue)
SELECT DATE(sold_at), branch, COUNT(*), SUM(qty * unit_price)
FROM sales
GROUP BY DATE(sold_at), branch;

SELECT * FROM daily_branch_sales ORDER BY sale_date, branch;
-- ❓ ถ้ารัน INSERT ข้างบนซ้ำจะเกิดอะไร? (ลองดู: duplicate key) บทที่ 8 จะสอนทำให้รันซ้ำได้

-- สรุปบทที่ 4
--   COUNT(*) vs COUNT(col) vs COUNT(DISTINCT) · GROUP BY · WHERE vs HAVING · ลำดับการทำงาน SQL
--   conditional aggregation (pivot) · WITH ROLLUP · INSERT ... SELECT เก็บผลสรุป
--   ➡️ ทำ Assignment A2
