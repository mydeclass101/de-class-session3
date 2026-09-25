# Assignment A5: Mini pipeline: incremental + SCD2 + DQ (หลังบทที่ 9)

**เป้าหมาย:** เขียน SQL script ที่ใช้เป็น "job" ได้จริง: รันซ้ำได้ (idempotent), โหลดเฉพาะส่วนที่เปลี่ยน, เก็บประวัติ, ตรวจคุณภาพ
อ่านจาก `ecommerce` → เขียนลง `lab_<ชื่อ>`
ส่ง 2 ไฟล์:
- `A5_setup_<ชื่อ>.sql`: DDL ทั้งหมด (รันครั้งเดียว)
- `A5_job_<ชื่อ>.sql`: job ที่รันซ้ำได้

## ขั้นตอนทดสอบ (ทดสอบเองแบบนี้ก่อนส่ง ผู้สอนจะตรวจด้วยขั้นตอนเดียวกัน)

1. รัน setup → รัน job (รอบที่ 1 = initial load)
2. รัน job ซ้ำทันที → **ต้องไม่มีอะไรเปลี่ยน** (ไม่มีแถวใหม่/ซ้ำ, log บอก 0)
3. ทำให้ข้อมูลต้นทางเดินหน้า 1 step: `docker compose exec mysql sh /scripts/advance.sh`
4. รัน job อีกครั้ง → ต้องได้ข้อมูลใหม่ + การเปลี่ยนแปลงครบ และ DQ ผ่านทุกข้อ
5. ทำข้อ 3–4 ซ้ำได้ตามจำนวน step ที่มี ถ้าต้องการเริ่มใหม่ทั้งหมด: `docker compose down -v` แล้ว `docker compose up -d`

## Part A: Incremental load ของ payments (35 คะแนน)

- ตาราง `stg_payments` (เลือกคอลัมน์ที่จำเป็นเอง, primary key = `payment_id`)
- โหลดแบบ watermark บน `ecommerce.payments.updated_at` + upsert
  (payment เปลี่ยนสถานะได้ เช่น `pending → success → refunded`)
- ใช้ **lookback 1 ชั่วโมง** (ดึงย้อนจาก watermark 1 ชั่วโมง) และอธิบายใน comment ว่าทำไมปลอดภัย
- บันทึก `etl_load_log`: เวลา, ช่วง watermark, จำนวนแถวใหม่, จำนวนแถวที่เปลี่ยน

## Part B: SCD Type 2 ของลูกค้า (35 คะแนน)

- ตาราง `dim_customer_scd2`: เก็บประวัติของ `membership_tier` และ `status` ของ `ecommerce.customers`
  (surrogate key, `valid_from`, `valid_to`, `is_current`)
- initial load: เวอร์ชันแรกของลูกค้าแต่ละคน `valid_from` = `registered_at`
- รอบถัดไป: เวอร์ชันใหม่ `valid_from` = `updated_at` ของ source (ไม่ใช่เวลาที่รัน job) และปิดเวอร์ชันเก่าที่เวลาเดียวกัน
  (ลูกค้าที่ `updated_at` เปลี่ยนแต่ tier/status ไม่เปลี่ยน ต้อง **ไม่** เกิดเวอร์ชันใหม่)
- หลังขั้นตอนที่ 4 ต้องมีลูกค้าอย่างน้อยบางคนที่มี 2 เวอร์ชัน (tier อัปเกรดเมื่อ order completed)
- เขียน query: "จำนวนลูกค้าแต่ละ tier ณ วันที่ `<วันใดก็ได้>`" จาก dim นี้

## Part C: Data quality (20 คะแนน)

ตาราง `dq_results` + INSERT ผลของ check อย่างน้อย 6 ข้อทุกครั้งที่รัน job:
1. `stg_payments`: จำนวนแถวเท่ากับ source (ถึง watermark)
2. `stg_payments`: ไม่มี `payment_id` ซ้ำ / NULL
3. `stg_payments.status` อยู่ในชุดค่าที่อนุญาต
4. `dim_customer_scd2`: ลูกค้าทุกคนมี **เวอร์ชันปัจจุบันเพียง 1 แถว**
5. `dim_customer_scd2`: ช่วงเวลาของแต่ละลูกค้าไม่ซ้อนกันและต่อเนื่อง (valid_to ของแถวก่อน = valid_from ของแถวถัดไป)
6. `dim_customer_scd2`: เวอร์ชันปัจจุบันตรงกับค่าใน source

## Part D: ตอบคำถาม (10 คะแนน, เขียนใน comment ท้าย job)

1. ถ้า source **ลบ** แถว payment ทิ้ง (hard delete) pipeline นี้จะรู้ไหม ควรแก้อย่างไร
2. ทำไมต้องล็อกค่าขอบบนของ watermark ก่อนเริ่มโหลด แทนที่จะใช้ `NOW()` ตอนจบ
3. ถ้า job พังระหว่าง Part A กับ Part B ข้อมูลปลายทางจะอยู่ในสถานะไหน ออกแบบอย่างไรให้รันใหม่แล้วถูกต้อง
