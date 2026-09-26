-- =====================================================================
--  บทที่ 3: SELECT พื้นฐาน: ดึง กรอง เรียง แปลงข้อมูล
--  ข้อมูล: เมนูร้านกาแฟ 12 รายการ (เห็นผลลัพธ์ครบทุกแถว ตรวจด้วยตาได้)
-- =====================================================================
USE lab_student;   -- ⚠️ แก้เป็น database ของตัวเอง

DROP TABLE IF EXISTS menu;
CREATE TABLE menu (
    product_id        INT           NOT NULL PRIMARY KEY,
    sku               VARCHAR(20)   NOT NULL UNIQUE,
    name              VARCHAR(100)  NOT NULL,
    category          VARCHAR(20)   NOT NULL,
    price             DECIMAL(8,2)  NOT NULL,
    cost              DECIMAL(8,2)  NOT NULL,
    stock             INT           NOT NULL,
    launched_date     DATE          NOT NULL,
    discontinued_date DATE          NULL,
    note              VARCHAR(200)  NULL
);
INSERT INTO menu VALUES
 ( 1, 'COF-ESP-001', 'Espresso',          'coffee', 55,  12, 100, '2025-01-01', NULL,         NULL),
 ( 2, 'COF-AME-002', 'Americano',         'coffee', 60,  13, 100, '2025-01-01', NULL,         'ขายดีตอนเช้า'),
 ( 3, 'COF-LAT-003', 'Latte',             'coffee', 70,  18,  80, '2025-01-01', NULL,         NULL),
 ( 4, 'COF-MOC-004', 'Mocha',             'coffee', 75,  20,  60, '2025-03-15', NULL,         NULL),
 ( 5, 'COF-COC-005', 'Coconut Cold Brew', 'coffee', 95,  30,  25, '2026-04-01', NULL,         'เมนูหน้าร้อน'),
 ( 6, 'TEA-THA-001', 'ชาไทย',              'tea',    55,  10, 120, '2025-01-01', NULL,         NULL),
 ( 7, 'TEA-MAT-002', 'มัทฉะลาเต้',          'tea',    80,  25,  40, '2025-06-01', NULL,         NULL),
 ( 8, 'TEA-LEM-003', 'ชามะนาว',            'tea',    50,   9,   0, '2025-01-01', '2025-12-31', 'เลิกขาย'),
 ( 9, 'BAK-CRO-001', 'Croissant',         'bakery', 65,  22,  30, '2025-02-01', NULL,         NULL),
 (10, 'BAK-BRW-002', 'Brownie',           'bakery', 59,  15,  45, '2025-02-01', NULL,         NULL),
 (11, 'BAK-CHC-003', 'Cheesecake',        'bakery', 95,  35,   8, '2025-08-01', NULL,         NULL),
 (12, 'MER-TUM-001', 'แก้วเก็บความเย็น',      'merch', 490, 210,  15, '2025-11-01', NULL,         NULL);

-- ---------------------------------------------------------------------
-- 3.1 เลือกคอลัมน์ + ตั้งชื่อ (alias) + คำนวณ
-- ---------------------------------------------------------------------
SELECT * FROM menu;                                   -- ⚠️ ใช้แค่สำรวจ: ใน pipeline ให้ระบุคอลัมน์เสมอ

SELECT sku, name, price FROM menu;

SELECT name,
       price,
       cost,
       price - cost                          AS profit,
       ROUND((price - cost) / price * 100, 1) AS margin_pct
FROM menu;

-- ---------------------------------------------------------------------
-- 3.2 WHERE: กรองแถว
-- ---------------------------------------------------------------------
SELECT name, price FROM menu WHERE category = 'coffee';
SELECT name, price FROM menu WHERE price > 70;
SELECT name, price FROM menu WHERE price BETWEEN 55 AND 65;          -- รวมขอบ 55 และ 65
SELECT name, category FROM menu WHERE category IN ('tea', 'bakery');
SELECT name FROM menu WHERE category <> 'coffee';                    -- ไม่เท่ากับ
SELECT name FROM menu WHERE name LIKE 'C%';                          -- ขึ้นต้นด้วย C
SELECT name FROM menu WHERE name LIKE '%ชา%';                        -- มีคำว่า ชา
SELECT sku FROM menu WHERE sku LIKE '___-___-00_';                   -- _ = อักขระ 1 ตัว
SELECT name, launched_date FROM menu WHERE launched_date >= '2025-06-01';

-- AND / OR: ⚠️ AND ทำก่อน OR เสมอ ใส่วงเล็บให้ชัด
SELECT name, category, price FROM menu
WHERE category = 'coffee' OR category = 'tea' AND price > 70;        -- ❓ ได้ Espresso ด้วย ทำไม?
SELECT name, category, price FROM menu
WHERE (category = 'coffee' OR category = 'tea') AND price > 70;      -- ✅ ตั้งใจแบบนี้

-- ---------------------------------------------------------------------
-- 3.3 NULL: "ไม่รู้ค่า" ไม่ใช่ 0 และไม่ใช่ข้อความว่าง
-- ---------------------------------------------------------------------
SELECT name, note FROM menu WHERE note = NULL;        -- ❌ ได้ 0 แถวเสมอ! NULL = NULL ไม่ใช่ TRUE
SELECT name, note FROM menu WHERE note IS NULL;       -- ✅
SELECT name, note FROM menu WHERE note IS NOT NULL;

SELECT NULL = NULL AS eq, NULL + 1 AS plus, 'a' = NULL AS cmp;       -- ทุกอย่างที่เจอ NULL = NULL

SELECT name,
       COALESCE(note, '-')                          AS note_display, -- แทน NULL ด้วยค่าอื่น
       COALESCE(discontinued_date, '9999-12-31')    AS active_until
FROM menu;

-- ⚠️ กับดัก NOT IN + NULL
SELECT name FROM menu WHERE note NOT IN ('เลิกขาย');                 -- แถวที่ note เป็น NULL หายไปด้วย!
SELECT name FROM menu WHERE note NOT IN ('เลิกขาย') OR note IS NULL; -- ✅

-- ---------------------------------------------------------------------
-- 3.4 ORDER BY, LIMIT, DISTINCT
-- ---------------------------------------------------------------------
SELECT name, price FROM menu ORDER BY price DESC;                    -- แพงสุดก่อน
SELECT name, category, price FROM menu ORDER BY category, price DESC;-- เรียงหลายชั้น
SELECT name, price FROM menu ORDER BY price DESC LIMIT 3;            -- top 3
SELECT name, price FROM menu ORDER BY price DESC LIMIT 3 OFFSET 3;   -- อันดับ 4-6 (แบ่งหน้า)
SELECT DISTINCT category FROM menu;                                  -- ค่าไม่ซ้ำ
SELECT DISTINCT category, stock > 0 AS in_stock FROM menu ORDER BY category;

-- ⚠️ ไม่มี ORDER BY = ไม่รับประกันลำดับ แม้ผลดูเหมือนเรียงอยู่แล้วก็ตาม

-- ---------------------------------------------------------------------
-- 3.5 ฟังก์ชันที่ใช้บ่อยตอน clean / transform ข้อมูล
-- ---------------------------------------------------------------------
-- ข้อความ
SELECT sku,
       LEFT(sku, 3)                     AS category_code,     -- 'COF'
       SUBSTRING_INDEX(sku, '-', -1)    AS running_no,        -- ส่วนสุดท้ายหลัง '-'
       UPPER(name)                      AS upper_name,
       CONCAT(name, ' (', category, ')') AS label,
       CHAR_LENGTH(name)                AS n_chars,           -- จำนวนตัวอักษร
       LENGTH(name)                     AS n_bytes,           -- จำนวน byte (ภาษาไทย 1 ตัว = 3 byte!)
       TRIM('  ชาไทย  ')                 AS trimmed,
       REPLACE(sku, '-', '')            AS sku_no_dash
FROM menu;

-- ตัวเลข
SELECT price, ROUND(price * 1.07, 2) AS with_vat, FLOOR(price / 7) AS f, CEIL(price / 7) AS c, MOD(stock, 12) AS m
FROM menu;

-- วันเวลา
SELECT name,
       launched_date,
       YEAR(launched_date)                       AS y,
       MONTH(launched_date)                      AS m,
       DATE_FORMAT(launched_date, '%Y-%m')       AS year_month,
       DAYNAME(launched_date)                    AS weekday,
       DATEDIFF('2026-09-01', launched_date)     AS days_on_menu,
       DATE_ADD(launched_date, INTERVAL 30 DAY)  AS promo_end,
       LAST_DAY(launched_date)                   AS month_end
FROM menu;

SELECT CURRENT_DATE AS today, NOW() AS now_, CAST('2026-03-15 13:45:00' AS DATE) AS only_date;

-- ---------------------------------------------------------------------
-- 3.6 CASE WHEN: สร้างคอลัมน์ตามเงื่อนไข (ใช้บ่อยมากตอนทำ business rule)
-- ---------------------------------------------------------------------
SELECT name,
       price,
       CASE WHEN price >= 90 THEN 'premium'
            WHEN price >= 60 THEN 'regular'
            ELSE 'value' END                                    AS price_tier,
       CASE WHEN discontinued_date IS NOT NULL THEN 'discontinued'
            WHEN stock = 0 THEN 'out_of_stock'
            WHEN stock < 20 THEN 'low_stock'
            ELSE 'ok' END                                       AS stock_status
FROM menu
ORDER BY price DESC;


-- อาจได้ผลที่แตกต่างกัน

SELECT name,
       price,
       CASE WHEN price >= 90 THEN 'premium'
            WHEN price >= 60 THEN 'regular'
            WHEN price >= 30 THEN 'eco'
            ELSE 'value' END                                    AS price_tier,
FROM menu
ORDER BY price DESC;

SELECT name,
       price,
       CASE WHEN price >= 30 THEN 'eco'
            WHEN price >= 60 THEN 'regular'
            WHEN price >= 90 THEN 'premium'
            ELSE 'value' END                                    AS price_tier,
FROM menu
ORDER BY price DESC;

-- หรืออาจจะใช้ between

SELECT name,
       price,
       CASE WHEN price BETWEEN 30 AND 59 THEN 'eco'
            WHEN price BETWEEN 60 AND 89 THEN 'regular'
            WHEN price >= 90 THEN 'premium'
            ELSE 'value' END                                    AS price_tier,
FROM menu
ORDER BY price DESC;


-- สรุปบทที่ 3
--   SELECT/alias/คำนวณ · WHERE (IN, BETWEEN, LIKE, วงเล็บ AND/OR) · NULL ต้องใช้ IS NULL / COALESCE
--   ORDER BY / LIMIT / DISTINCT · ฟังก์ชันข้อความ ตัวเลข วันที่ · CASE WHEN
