-- =====================================================================
--  บทที่ 2: DML (Data Manipulation Language): จัดการ "ข้อมูล" ในตาราง
--  INSERT · UPDATE · DELETE · TRUNCATE · TRANSACTION
-- =====================================================================
USE lab_student;   -- ⚠️ แก้เป็น database ของตัวเอง

DROP TABLE IF EXISTS members;
CREATE TABLE members (
    member_id    INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    member_code  VARCHAR(12)  NOT NULL UNIQUE,
    name         VARCHAR(200) NOT NULL,
    province     VARCHAR(50)  NOT NULL DEFAULT 'กรุงเทพมหานคร',
    tier         VARCHAR(10)  NOT NULL DEFAULT 'bronze',
    points       INT          NOT NULL DEFAULT 0,
    joined_date  DATE         NOT NULL,
    created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT ck_points CHECK (points >= 0),
    CONSTRAINT ck_tier   CHECK (tier IN ('bronze','silver','gold'))
);

-- ---------------------------------------------------------------------
-- 2.1 INSERT
-- ---------------------------------------------------------------------
-- แบบ 1 แถว + ระบุคอลัมน์ (✅ แนะนำเสมอ: ตารางเพิ่มคอลัมน์ในอนาคตก็ไม่พัง)
INSERT INTO members (member_code, name, province, points, joined_date)
VALUES ('MEM-0001', 'สมชาย ใจดี', 'กรุงเทพมหานคร', 120, '2026-01-15');

-- แบบหลายแถวในคำสั่งเดียว (💡 เร็วกว่า INSERT ทีละแถวมาก: bulk insert)
INSERT INTO members (member_code, name, province, points, joined_date) VALUES
    ('MEM-0002', 'สมหญิง รักสวย', 'เชียงใหม่',  80, '2026-01-20'),
    ('MEM-0003', 'วิชัย มั่นคง',   'ขอนแก่น',     0, '2026-02-03'),
    ('MEM-0004', 'นภา ศรีสุข',    'ภูเก็ต',     450, '2026-02-14'),
    ('MEM-0005', 'ธนพล ทองดี',    'ชลบุรี',     230, '2026-03-01');

-- ไม่ระบุคอลัมน์ที่มี default → ใช้ default
INSERT INTO members (member_code, name, joined_date) VALUES ('MEM-0006', 'ปิยะ บุญมา', '2026-03-05');

SELECT * FROM members;

-- ---------------------------------------------------------------------
-- 2.2 UPDATE: ⚠️ ต้องมี WHERE เสมอ ไม่งั้นแก้ "ทุกแถว"
-- ---------------------------------------------------------------------
UPDATE members
SET points = points + 50            -- คำนวณจากค่าเดิมได้

-- 💡 เทคนิค: เขียน SELECT ด้วย WHERE เดียวกันก่อน ดูว่าโดนกี่แถว แล้วค่อยเปลี่ยนเป็น UPDATE
SELECT * FROM members WHERE member_code = 'MEM-0003';

UPDATE members
SET points = points + 50            -- คำนวณจากค่าเดิมได้
WHERE member_code = 'MEM-0003';

-- แก้หลายคอลัมน์ + หลายแถวพร้อมกัน
UPDATE members
SET tier = 'silver'
WHERE points >= 200;

-- UPDATE ด้วยเงื่อนไขแบบ CASE (อัปเดต tier ใหม่ทั้งหมดในคำสั่งเดียว)
UPDATE members
SET tier = CASE WHEN points >= 400 THEN 'gold'
                WHEN points >= 200 THEN 'silver'
                ELSE 'bronze' END
WHERE member_id > 0;                -- WHERE ที่ครอบทุกแถว (บาง tool บังคับให้มี WHERE)

SELECT member_code, points, tier, created_at, updated_at FROM members;
-- 👀 สังเกต updated_at ของแถวที่ถูกแก้ จะใหม่กว่า created_at (ถ้ารันห่างกันเกิน 1 วินาที)

-- ---------------------------------------------------------------------
-- 2.3 DELETE: ⚠️ ต้องมี WHERE เสมอเช่นกัน
-- ---------------------------------------------------------------------
SELECT * FROM members WHERE member_code = 'MEM-0006';
DELETE FROM members WHERE member_code = 'MEM-0006';
SELECT COUNT(*) AS remaining FROM members;

-- 💡 Hard delete vs Soft delete
--    hard delete = ลบแถวจริง → pipeline ที่ดึงตาม updated_at "มองไม่เห็น" ว่าแถวหายไป
--    soft delete = ใส่ is_deleted = 1 / deleted_at แทน → ระบบปลายทางรู้ว่าถูกลบ
ALTER TABLE members ADD COLUMN deleted_at DATETIME;
UPDATE members SET deleted_at = NOW() WHERE member_code = 'MEM-0005';
SELECT member_code, name, deleted_at FROM members WHERE deleted_at IS NULL;   -- สมาชิกที่ยัง active

ALTER TABLE members ADD COLUMN is_active BOOLEAN;

update members 
set is_active = 1
where deleted_at is null;

SELECT * FROM members WHERE is_active = true;

-- ---------------------------------------------------------------------
-- 2.4 TRANSACTION: ทำหลายคำสั่งแบบ "สำเร็จทั้งหมด หรือไม่เกิดอะไรเลย"
-- ---------------------------------------------------------------------
-- ตัวอย่าง: โอนแต้มจาก MEM-0004 ไป MEM-0002 จำนวน 100 แต้ม
START TRANSACTION;
UPDATE members SET points = points - 100 WHERE member_code = 'MEM-0004';
UPDATE members SET points = points + 100 WHERE member_code = 'MEM-0002';
SELECT member_code, points FROM members WHERE member_code IN ('MEM-0002','MEM-0004');
COMMIT;                                  -- ยืนยัน: บันทึกถาวร

-- ROLLBACK = ย้อนกลับทุกอย่างตั้งแต่ START TRANSACTION
START TRANSACTION;
UPDATE members SET points = 0;           -- 😱 ลืม WHERE! ทุกคนแต้มเป็น 0
SELECT member_code, points FROM members;
ROLLBACK;                                -- 😮‍💨 ย้อนกลับ
SELECT member_code, points FROM members; -- แต้มกลับมาเหมือนเดิม

-- 💡 งาน pipeline: โหลดข้อมูลหลายขั้นใน transaction เดียว ถ้าพังกลางทาง ปลายทางจะไม่ค้างครึ่ง ๆ กลาง ๆ
-- ⚠️ DDL (CREATE/ALTER/DROP/TRUNCATE) ใน MySQL จะ COMMIT อัตโนมัติ และ ROLLBACK ไม่ได้

-- ---------------------------------------------------------------------
-- 2.5 DELETE ทั้งหมด vs TRUNCATE
-- ---------------------------------------------------------------------
CREATE TABLE members_copy LIKE members;
INSERT INTO members_copy SELECT * FROM members;           -- copy ข้อมูลจากอีกตาราง (INSERT ... SELECT)
SELECT COUNT(*) FROM members_copy;

CREATE TABLE members_bk AS SELECT * FROM members;

DELETE FROM members_copy WHERE member_id > 0;             -- ลบทีละแถว, ROLLBACK ได้, ช้าในตารางใหญ่
INSERT INTO members_copy (member_code, name, joined_date) VALUES ('MEM-9999', 'ทดสอบ', '2026-04-01');
SELECT member_id FROM members_copy;                       -- id ต่อจากเดิม (AUTO_INCREMENT ไม่ reset)

TRUNCATE TABLE members_copy;                              -- ล้างทั้งตารางทันที, reset AUTO_INCREMENT, ROLLBACK ไม่ได้
INSERT INTO members_copy (member_code, name, joined_date) VALUES ('MEM-9999', 'ทดสอบ', '2026-04-01');
SELECT member_id FROM members_copy;                       -- กลับมาเริ่มที่ 1
DROP TABLE members_copy;

-- สรุปบทที่ 2
--   INSERT (หลายแถว = เร็ว) · UPDATE/DELETE ต้องมี WHERE และลอง SELECT ก่อน
--   Transaction = COMMIT / ROLLBACK · soft delete · DELETE vs TRUNCATE
--   ➡️ ทำ Assignment A1
