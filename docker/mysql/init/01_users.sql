-- Runs once, on the first start (empty volume).

-- class account: read-only on the shop data, full rights on your own lab_<name> databases
CREATE USER IF NOT EXISTS 'student'@'%' IDENTIFIED BY 'student123';
GRANT SELECT, SHOW VIEW ON ecommerce.* TO 'student'@'%';
GRANT ALL PRIVILEGES ON `lab\_%`.* TO 'student'@'%';

-- which data steps (scripts/advance.sh) have been applied
CREATE DATABASE IF NOT EXISTS course_meta CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE TABLE IF NOT EXISTS course_meta.applied_steps (
    step        INT PRIMARY KEY,
    applied_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
GRANT SELECT ON course_meta.* TO 'student'@'%';

FLUSH PRIVILEGES;
