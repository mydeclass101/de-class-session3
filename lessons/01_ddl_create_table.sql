-- =====================================================================
--  บทที่ 1: DDL (Data Definition Language): สร้าง/แก้/ลบ "โครงสร้าง" ตาราง
--  CREATE · ALTER · DROP · RENAME   (ยังไม่แตะข้อมูลข้างใน)
-- =====================================================================
USE lab_student;   -- ⚠️ แก้เป็น database ของตัวเอง

-- ---------------------------------------------------------------------
-- 1.1 ตารางแรก: สมาชิกร้านกาแฟ (แบบง่ายที่สุด)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS members;          -- ให้ script รันซ้ำได้ (idempotent)

CREATE TABLE members (
    member_id    INT,
    name         VARCHAR(100),
    province     VARCHAR(50),
    joined_date  DATE,
    points       INT
);

-- ดูโครงสร้างตาราง
DESCRIBE members;
SHOW CREATE TABLE members;             -- DDL เต็มที่ MySQL เก็บไว้จริง

-- ลองใส่ข้อมูล 1 แถวเพื่อดูว่าตารางใช้งานได้ (รายละเอียด INSERT อยู่บทที่ 2)
INSERT INTO members VALUES (1, 'สมชาย', 'กรุงเทพมหานคร', '2026-01-15', 120);
SELECT * FROM members;

-- ⚠️ ตารางนี้ยังมีปัญหา: ไม่มีอะไรกันข้อมูลแย่ ๆ เลย
INSERT INTO members VALUES (1, NULL, NULL, NULL, -50);    -- id ซ้ำ, ไม่มีชื่อ, แต้มติดลบ ... ใส่ได้หมด!
SELECT * FROM members;

-- ---------------------------------------------------------------------
-- 1.2 Data types ที่ใช้บ่อยในงาน DE
-- ---------------------------------------------------------------------
--  จำนวนเต็ม     TINYINT (±127) · SMALLINT · INT (±2.1 พันล้าน) · BIGINT (id ของตารางใหญ่)
--  ทศนิยม        DECIMAL(12,2): เงิน **ต้องใช้ DECIMAL** ห้ามใช้ FLOAT/DOUBLE (ปัดเศษเพี้ยน)
--  ข้อความ       VARCHAR(n) ความยาวไม่เกิน n · CHAR(n) ความยาวคงที่ (เช่น รหัสไปรษณีย์) · TEXT ยาวมาก
--  วันเวลา       DATE · DATETIME (วัน+เวลา) · TIMESTAMP (เก็บเป็น UTC แปลงตาม time zone)
--  จริง/เท็จ     BOOLEAN (= TINYINT(1): 1/0)
--  JSON          JSON (ข้อมูลกึ่งโครงสร้างจาก API)

-- 💡 ทำไม DECIMAL สำคัญกับเงิน: ลองดู
SELECT 0.1 + 0.2 = 0.3                              AS decimal_math,   -- 1 (จริง)
       CAST(0.1 AS DOUBLE) + CAST(0.2 AS DOUBLE) = 0.3 AS float_math;  -- 0 (เท็จ!)

-- ---------------------------------------------------------------------
-- 1.3 ตารางที่ดี: ใส่ constraints ให้ database ช่วยกันข้อมูลเสีย
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS members;

CREATE TABLE members (
    member_id    INT          NOT NULL AUTO_INCREMENT,           -- เลขรันอัตโนมัติ
    member_code  VARCHAR(12)  NOT NULL,                          -- business key เช่น MEM-0001
    name         VARCHAR(100) NOT NULL,                          -- ห้ามว่าง
    phone        VARCHAR(20)  NULL,                              -- ว่างได้
    province     VARCHAR(50)  NOT NULL DEFAULT 'กรุงเทพมหานคร',  -- ไม่ใส่ = ค่า default
    tier         VARCHAR(10)  NOT NULL DEFAULT 'bronze',
    points       INT          NOT NULL DEFAULT 0,
    joined_date  DATE         NOT NULL,
    created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (member_id),                                     -- ห้ามซ้ำ + ห้าม NULL
    UNIQUE KEY uq_members_code (member_code),                    -- ห้ามซ้ำ
    CONSTRAINT ck_members_points CHECK (points >= 0),            -- กฎทางธุรกิจ
    CONSTRAINT ck_members_tier   CHECK (tier IN ('bronze','silver','gold'))
);

-- 💡 created_at / updated_at คือหัวใจของงาน DE
--    updated_at จะเปลี่ยนเองทุกครั้งที่แถวถูก UPDATE → ใช้ดึง "เฉพาะแถวที่เปลี่ยน" (incremental load, บทที่ 8)
--    ตารางจริงใน ecommerce มีสองคอลัมน์นี้ทุกตารางที่ข้อมูลเปลี่ยนได้

INSERT INTO members (member_code, name, joined_date) VALUES ('MEM-0001', 'สมชาย ใจดี', '2026-01-15');
SELECT * FROM members;                 -- member_id, province, tier, points, created_at ถูกเติมให้อัตโนมัติ

-- ลองใส่ข้อมูลเสีย: ทุกบรรทัดจะ error (ลบ -- ออกทีละบรรทัดแล้วรัน)
-- ❌ INSERT INTO members (member_code, name, joined_date) VALUES ('MEM-0001', 'ซ้ำ', '2026-01-16');           -- Duplicate entry (UNIQUE)
-- ❌ INSERT INTO members (member_code, joined_date) VALUES ('MEM-0002', '2026-01-16');                        -- name ไม่มี default (NOT NULL)
-- ❌ INSERT INTO members (member_code, name, points, joined_date) VALUES ('MEM-0003', 'ก', -5, '2026-01-16');  -- CHECK points
-- ❌ INSERT INTO members (member_code, name, tier, joined_date) VALUES ('MEM-0004', 'ข', 'vip', '2026-01-16'); -- CHECK tier

-- ---------------------------------------------------------------------
-- 1.4 ALTER TABLE: แก้โครงสร้างตารางที่มีอยู่แล้ว (ข้อมูลเดิมยังอยู่)
-- ---------------------------------------------------------------------
ALTER TABLE members ADD COLUMN email VARCHAR(255) NULL AFTER phone;        -- เพิ่มคอลัมน์
ALTER TABLE members MODIFY COLUMN name VARCHAR(200) NOT NULL;               -- เปลี่ยน type/ขนาด
ALTER TABLE members RENAME COLUMN phone TO phone_number;                    -- เปลี่ยนชื่อคอลัมน์
ALTER TABLE members ADD COLUMN birth_date DATE NULL;
ALTER TABLE members DROP COLUMN birth_date;                                 -- ลบคอลัมน์ (ข้อมูลในคอลัมน์หายด้วย)
ALTER TABLE members ADD INDEX ix_members_joined (joined_date);              -- index ช่วยค้นหาเร็ว (บทที่ 9)
DESCRIBE members;

-- ⚠️ ALTER บนตารางใหญ่ใน production อาจล็อกตารางนาน ต้องวางแผน (ทำนอกเวลาทำงาน / ใช้เครื่องมือ online DDL)
-- ⚠️ ในงาน pipeline เมื่อ source เพิ่มคอลัมน์ ("schema change") ตารางปลายทางก็ต้อง ALTER ตาม

-- ---------------------------------------------------------------------
-- 1.5 RENAME / DROP
-- ---------------------------------------------------------------------
CREATE TABLE members_backup LIKE members;          -- copy "โครงสร้าง" อย่างเดียว (ไม่มีข้อมูล)
SHOW TABLES;
RENAME TABLE members_backup TO members_old;
DROP TABLE members_old;                            -- ลบทั้งตาราง (โครงสร้าง + ข้อมูล) กู้คืนไม่ได้!
DROP TABLE IF EXISTS table_that_does_not_exist;    -- IF EXISTS = ไม่ error ถ้าไม่มี
SHOW TABLES;

-- ---------------------------------------------------------------------
-- 1.6 ดู metadata ของตาราง (DE ใช้บ่อยมากตอนสำรวจ source ใหม่)
-- ---------------------------------------------------------------------
SELECT column_name, data_type, is_nullable, column_default, column_key
FROM information_schema.columns
WHERE table_schema = DATABASE() AND table_name = 'members'
ORDER BY ordinal_position;

-- สรุปบทที่ 1
--   CREATE TABLE (type + constraints) · DESCRIBE / SHOW CREATE TABLE · ALTER TABLE · RENAME · DROP
--   Constraint = ด่านแรกของ data quality: ให้ database ปฏิเสธข้อมูลเสียตั้งแต่ตอนเขียน
