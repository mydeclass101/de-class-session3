-- =====================================================================
--  Seed สำหรับ Assignment A3: mini shop (เหมือนบทที่ 5 + ข้อมูลเพิ่ม) รันไฟล์นี้ก่อนทำ A3
-- =====================================================================
USE lab_student;   -- ⚠️ แก้เป็น database ของตัวเอง

-- ลบตามลำดับ "ลูก → แม่" (ตารางที่ถูกอ้างอิงลบทีหลัง)
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;

-- ---------------------------------------------------------------------
-- 5.1 DDL: ตารางที่อ้างอิงกัน
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    customer_id    INT          NOT NULL PRIMARY KEY,           -- surrogate key (ตัวเลขภายในระบบ)
    customer_code  VARCHAR(12)  NOT NULL UNIQUE,                -- business key (คนใช้จริง)
    name           VARCHAR(100) NOT NULL,
    province       VARCHAR(50)  NOT NULL,
    registered_at  DATETIME     NOT NULL
);

CREATE TABLE products (
    product_id  INT           NOT NULL PRIMARY KEY,
    sku         VARCHAR(20)   NOT NULL UNIQUE,
    name        VARCHAR(100)  NOT NULL,
    category    VARCHAR(30)   NOT NULL,
    price       DECIMAL(10,2) NOT NULL
);

CREATE TABLE orders (
    order_id      INT          NOT NULL PRIMARY KEY,
    order_number  VARCHAR(20)  NOT NULL UNIQUE,
    customer_id   INT          NOT NULL,
    ordered_at    DATETIME     NOT NULL,
    status        VARCHAR(20)  NOT NULL,
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
        -- default = ON DELETE RESTRICT: ห้ามลบลูกค้าที่ยังมี order
);

CREATE TABLE order_items (
    order_id     INT           NOT NULL,
    line_number  INT           NOT NULL,
    product_id   INT           NOT NULL,
    quantity     INT           NOT NULL CHECK (quantity > 0),
    unit_price   DECIMAL(10,2) NOT NULL,                 -- ราคา ณ วันที่ขาย (สินค้าอาจเปลี่ยนราคาทีหลัง)
    PRIMARY KEY (order_id, line_number),                 -- composite primary key
    CONSTRAINT fk_items_order   FOREIGN KEY (order_id)   REFERENCES orders (order_id) ON DELETE CASCADE,
    CONSTRAINT fk_items_product FOREIGN KEY (product_id) REFERENCES products (product_id)
);

CREATE TABLE payments (
    payment_id  INT           NOT NULL PRIMARY KEY,
    order_id    INT           NOT NULL,
    attempt     INT           NOT NULL,
    method      VARCHAR(20)   NOT NULL,
    amount      DECIMAL(10,2) NOT NULL,
    status      VARCHAR(10)   NOT NULL,                  -- success / failed / pending
    CONSTRAINT fk_payments_order FOREIGN KEY (order_id) REFERENCES orders (order_id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- 5.2 Seed data (ใส่ "แม่" ก่อน "ลูก")
-- ---------------------------------------------------------------------
INSERT INTO customers VALUES
 (1, 'CUS-0000001', 'สมชาย ใจดี',   'กรุงเทพมหานคร', '2026-01-05 10:00'),
 (2, 'CUS-0000002', 'สมหญิง รักสวย', 'เชียงใหม่',      '2026-01-10 19:30'),
 (3, 'CUS-0000003', 'วิชัย มั่นคง',   'ขอนแก่น',        '2026-02-01 08:15'),
 (4, 'CUS-0000004', 'นภา ศรีสุข',    'ภูเก็ต',         '2026-02-20 21:00'),
 (5, 'CUS-0000005', 'ธนพล ทองดี',    'ชลบุรี',         '2026-03-03 12:45'),
 (6, 'CUS-0000006', 'ปิยะ บุญมา',    'กรุงเทพมหานคร', '2026-03-15 09:00');   -- สมัครแล้วยังไม่เคยซื้อ

INSERT INTO products VALUES
 (1, 'ACC-ANK-00001', 'Anker สายชาร์จ USB-C',     'Electronics', 290),
 (2, 'AUD-SNY-00001', 'Sony หูฟังไร้สาย',          'Electronics', 3990),
 (3, 'SKN-MIS-00001', 'Mistine ครีมกันแดด 50ml',   'Beauty',      259),
 (4, 'SNK-TAS-00001', 'Tasto มันฝรั่งทอดกรอบ',      'Food',        35),
 (5, 'MEN-UNQ-00001', 'UNIQLO เสื้อยืดคอกลม ไซส์ M', 'Fashion',     390),
 (6, 'BKS-NMB-00001', 'Nanmeebooks หนังสือนิทาน',   'Books',       159);   -- ยังไม่เคยขายได้

INSERT INTO orders VALUES
 (101, 'ORD-260301-000001', 1, '2026-03-01 10:15', 'completed'),
 (102, 'ORD-260301-000002', 2, '2026-03-01 20:40', 'completed'),
 (103, 'ORD-260302-000001', 1, '2026-03-02 09:05', 'cancelled'),
 (104, 'ORD-260305-000001', 3, '2026-03-05 21:30', 'completed'),
 (105, 'ORD-260305-000002', 4, '2026-03-05 22:10', 'shipped'),
 (106, 'ORD-260310-000001', 1, '2026-03-10 12:00', 'completed'),
 (107, 'ORD-260310-000002', 5, '2026-03-10 19:45', 'pending_payment');

INSERT INTO order_items VALUES
 (101, 1, 1, 2, 290), (101, 2, 4, 3, 35),
 (102, 1, 3, 1, 259),
 (103, 1, 2, 1, 3990),
 (104, 1, 5, 2, 390), (104, 2, 4, 5, 35), (104, 3, 3, 1, 259),
 (105, 1, 2, 1, 3990),
 (106, 1, 1, 1, 290),
 (107, 1, 5, 1, 390);

INSERT INTO payments VALUES
 (1, 101, 1, 'card',      685,  'success'),
 (2, 102, 1, 'promptpay', 259,  'success'),
 (3, 103, 1, 'card',      3990, 'failed'),
 (4, 104, 1, 'card',      1214, 'failed'),      -- บัตรไม่ผ่าน
 (5, 104, 2, 'promptpay', 1214, 'success'),     -- ลองใหม่ด้วย promptpay
 (6, 105, 1, 'cod',       3990, 'pending'),
 (7, 106, 1, 'promptpay', 290,  'success');


-- ข้อมูลเพิ่มเติมสำหรับ assignment
INSERT INTO customers VALUES
 (7, 'CUS-0000007', 'กาญจนา แก้วมณี', 'เชียงใหม่',     '2026-03-20 14:00'),
 (8, 'CUS-0000008', 'อนุชา สายทอง',   'กรุงเทพมหานคร', '2026-03-25 20:30');
INSERT INTO orders VALUES
 (108, 'ORD-260320-000001', 7, '2026-03-20 15:10', 'completed'),
 (109, 'ORD-260322-000001', 2, '2026-03-22 21:05', 'completed'),
 (110, 'ORD-260326-000001', 8, '2026-03-26 08:40', 'cancelled');
INSERT INTO order_items VALUES
 (108, 1, 3, 2, 259), (108, 2, 5, 1, 390),
 (109, 1, 2, 1, 3790),                      -- ขายช่วงลดราคา (ราคาปกติ 3990)
 (109, 2, 1, 2, 290),
 (110, 1, 4, 10, 35);
INSERT INTO payments VALUES
 ( 8, 108, 1, 'card',      908,  'success'),
 ( 9, 109, 1, 'card',      4370, 'failed'),
 (10, 109, 2, 'card',      4370, 'failed'),
 (11, 109, 3, 'promptpay', 4370, 'success'),
 (12, 110, 1, 'promptpay', 350,  'failed');
