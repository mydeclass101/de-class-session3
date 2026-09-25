# SQL for Data Engineers: ชุดเรียนบนเครื่องตัวเอง

repo นี้มี **MySQL 8.4 พร้อมข้อมูลร้านค้าออนไลน์จำลอง** (ลูกค้า 5 หมื่นคน, order กว่า 2 แสนรายการ, ข้อมูลรวมหลายล้านแถว)
บทเรียน และการบ้าน ทุกคนได้ข้อมูลชุดเดียวกัน คำตอบจึงเทียบกันได้

## สิ่งที่ต้องมี

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (เปิดทิ้งไว้ก่อนรันคำสั่ง)
- git
- DBeaver
- พื้นที่ว่างประมาณ 3 GB

## เริ่มต้น (ครั้งแรก)

```bash
git clone <URL ของ repo นี้>
cd <ชื่อโฟลเดอร์>
docker compose up -d
```

ครั้งแรกจะใช้เวลาประมาณ 5–10 นาที เพราะต้อง **ดาวน์โหลดไฟล์ข้อมูล** (ไปไว้ที่ `data/ecommerce_base.sql.gz`) และ **restore ลง MySQL**
ดูความคืบหน้าได้ด้วย

```bash
docker compose logs -f mysql        # รอจนเห็น ">>> ecommerce restored" และ "ready for connections"  (Ctrl+C เพื่อออก)
docker compose ps                   # STATUS ต้องเป็น (healthy)
```

ครั้งต่อไปใช้แค่ `docker compose up -d` (เปิด) และ `docker compose stop` (ปิด) ข้อมูลยังอยู่ครบ

## เชื่อมต่อด้วย DBeaver

| ช่อง | ค่า |
|---|---|
| Host | `localhost` |
| Port | `3306` |
| Username / Password | `student` / `student123` |
| Driver properties | `allowPublicKeyRetrieval` = `true`, `useSSL` = `false` |

สิทธิ์ของ user `student`
- `ecommerce`: อ่านได้อย่างเดียว (ข้อมูลร้านค้า ใช้ตั้งแต่บทที่ 6)
- `lab_<ชื่อ>`: ทำได้ทุกอย่าง สร้างของตัวเองในบทที่ 0 เช่น `lab_somchai`

> ถ้าเครื่องมี MySQL ติดตั้งอยู่แล้ว (port 3306 ถูกใช้) ให้คัดลอก `.env.example` เป็น `.env` แล้วแก้ `MYSQL_PORT=3307`
> จากนั้น `docker compose up -d` อีกครั้ง และใช้ port 3307 ใน DBeaver

## เนื้อหาใน repo

```
lessons/        ไฟล์ SQL บทเรียน (รันใน DBeaver ทีละคำสั่งด้วย Ctrl+Enter)
assignments/    โจทย์การบ้าน A1–A5 (+ ไฟล์ seed ที่โจทย์บอกให้รันก่อน)
work/           ที่ทำงานของเราเอง (git ไม่สนใจโฟลเดอร์นี้)
data/           ไฟล์ข้อมูล + data steps (ไม่ต้องแก้)
scripts/        advance.sh ทำให้ข้อมูลเดินหน้า
```

**คัดลอกไฟล์บทเรียนไปไว้ใน `work/` ก่อนแก้** (เช่นแก้ `USE lab_student;` เป็นชื่อตัวเอง)
เวลาผู้สอนเพิ่มบทเรียนใหม่ จะได้ `git pull` ได้โดยไม่ชนกับไฟล์ที่เราแก้

| # | ไฟล์ | หัวข้อ | การบ้าน |
|---|---|---|---|
| 0 | `00_setup.sql` | เชื่อมต่อ, สร้าง sandbox ของตัวเอง | |
| 1 | `01_ddl_create_table.sql` | CREATE / ALTER / DROP, data types, constraints | |
| 2 | `02_dml_insert_update_delete.sql` | INSERT / UPDATE / DELETE, transaction | **A1** |
| 3 | `03_select_basics.sql` | SELECT, WHERE, ORDER BY, ฟังก์ชัน, CASE, NULL | |
| 4 | `04_aggregate_groupby.sql` | COUNT/SUM/AVG, GROUP BY, HAVING | **A2** |
| 5 | `05_relations_joins.sql` | PK/FK, INNER/LEFT JOIN, anti-join, fan-out, UNION | **A3** |
| 6 | `06_explore_real_data.sql` | สำรวจ schema จริง, lifecycle ของ 1 order | |
| 7 | `07_subquery_cte_window.sql` | Subquery, CTE, window functions, date spine | **A4** |
| 8 | `08_de_load_patterns.sql` | CTAS, INSERT…SELECT, UPSERT, incremental watermark, dedup | |
| 9 | `09_modeling_quality_performance.sql` | View, SCD Type 2, data quality, index + EXPLAIN | **A5** |

สัญลักษณ์ในไฟล์บทเรียน: `-- ❌` = คำสั่งที่ตั้งใจให้ error (ลบ `-- ` แล้วลองรัน), `💡` = ประเด็นที่ Data Engineer ต้องรู้,
`⚠️` = ความผิดพลาดที่พบบ่อย

## ทำให้ข้อมูลเดินหน้า (บทที่ 8 และ A5)

ระบบจริงมี order ใหม่และสถานะเปลี่ยนตลอดเวลา เราจำลองได้ด้วย **data step** ที่เตรียมไว้
(1 step = ข้อมูลเดินหน้า 1–2 วัน: order ใหม่, order เก่าเปลี่ยนสถานะ, การจ่ายเงิน, การจัดส่ง ฯลฯ)

```bash
docker compose exec mysql sh /scripts/advance.sh           # ใช้ step ถัดไป
docker compose exec mysql sh /scripts/advance.sh status    # ดูว่าใช้ไปกี่ step แล้ว
```

## เริ่มใหม่ทั้งหมด (reset)

ลบฐานข้อมูลทั้งหมด (รวม `lab_` ของเรา) แล้ว restore ข้อมูลตั้งต้นใหม่ **โค้ดที่เก็บไว้ใน `work/` ไม่หาย**

```bash
docker compose down -v
docker compose up -d
```

## อัปเดตบทเรียนใหม่

```bash
git pull
```

## แก้ปัญหาที่พบบ่อย

| อาการ | วิธีแก้ |
|---|---|
| `docker compose ps` ขึ้น `unhealthy` หรือค้างที่ `health: starting` นานผิดปกติ / ไม่มี database `ecommerce` | ดู `docker compose logs mysql` ถ้าดาวน์โหลดไม่สำเร็จ ให้ดาวน์โหลด `ecommerce_base.sql.gz` จากหน้า Releases ของ repo นี้มาวางใน `data/` แล้ว reset |
| DBeaver: `Public Key Retrieval is not allowed` | ตั้ง driver property `allowPublicKeyRetrieval` = `true` |
| DBeaver: `Access denied for user 'student'` | ตรวจ port (3306/3307) และรอให้สถานะเป็น `healthy` ก่อน |
| `port is already allocated` | ใช้ `.env` เปลี่ยน port ตามหัวข้อด้านบน |
