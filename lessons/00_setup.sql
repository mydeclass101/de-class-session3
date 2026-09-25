-- =====================================================================
--  บทที่ 0: เชื่อมต่อฐานข้อมูล และสร้าง sandbox ของตัวเอง
-- =====================================================================
--  เชื่อมต่อ (DBeaver → New Connection → MySQL)
--    Host: localhost   Port: 3306   User: student   Password: student123
--    (ถ้าเปลี่ยน MYSQL_PORT ใน .env ให้ใช้ port นั้นแทน)
--    Driver properties: allowPublicKeyRetrieval = true, useSSL = false
-- =====================================================================

-- 1) ทดสอบว่าเชื่อมต่อได้: ถามข้อมูลพื้นฐานจากเซิร์ฟเวอร์
SELECT CURRENT_USER() AS who_am_i, VERSION() AS mysql_version, NOW() AS server_time;

-- 2) database ที่เรามองเห็น
SHOW DATABASES;
--    ecommerce   = ข้อมูลร้านค้าออนไลน์จริง (อ่านได้อย่างเดียว) ใช้ตั้งแต่บทที่ 6
--    lab_xxx     = sandbox ของแต่ละคน ทำอะไรก็ได้

-- 3) สร้าง database ของตัวเอง
--    ⚠️ เปลี่ยน lab_student เป็นชื่อตัวเอง (ตัวเล็ก ไม่มีเว้นวรรค) เช่น lab_somchai
--    ชื่อ database ต้องขึ้นต้นด้วย lab_ เท่านั้น ถึงจะมีสิทธิ์สร้าง
CREATE DATABASE IF NOT EXISTS lab_student
    CHARACTER SET utf8mb4            -- รองรับภาษาไทยและ emoji
    COLLATE utf8mb4_0900_ai_ci;

-- 4) เลือกใช้ database นี้เป็นค่าเริ่มต้น (ทุกบทจะขึ้นต้นด้วยคำสั่งนี้)
USE lab_student;
SELECT DATABASE() AS current_database;

-- 5) ลองสิทธิ์: ecommerce อ่านได้ แต่เขียนไม่ได้
SELECT COUNT(*) AS total_orders FROM ecommerce.orders;
-- ❌ DELETE FROM ecommerce.orders WHERE order_id = 1;      -- ลบ comment แล้วรัน จะเจอ "command denied"

-- 💡 ชื่อเต็มของตารางคือ <database>.<table>
--    ถ้าไม่ใส่ database จะใช้ database ปัจจุบัน (ที่ USE ไว้)
