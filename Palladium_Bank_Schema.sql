-- ============================================================
-- PALLADIUM BANK: COMPLETE STAR SCHEMA
-- ============================================================

USE palladium_bank;

-- ============================================================
-- DROP EXISTING TABLES
-- ============================================================
DROP TABLE IF EXISTS FACT_TRANSACTIONS;
DROP TABLE IF EXISTS DIM_CUSTOMER;
DROP TABLE IF EXISTS DIM_BRANCH;
DROP TABLE IF EXISTS DIM_PRODUCT;
DROP TABLE IF EXISTS DIM_CHANNEL;
DROP TABLE IF EXISTS DIM_DATE;

-- ============================================================
-- CREATE TABLES
-- ============================================================

CREATE TABLE DIM_DATE (
    date_key        INT PRIMARY KEY,
    full_date       DATE NOT NULL,
    day_of_month    TINYINT,
    day_name        VARCHAR(10),
    week_number     TINYINT,
    month_number    TINYINT,
    month_name      VARCHAR(15),
    quarter         TINYINT,
    year            SMALLINT,
    is_weekend      TINYINT(1),
    is_month_end    TINYINT(1)
);

CREATE TABLE DIM_CUSTOMER (
    customer_key    INT AUTO_INCREMENT PRIMARY KEY,
    customer_id     VARCHAR(10) NOT NULL,
    customer_name   VARCHAR(100),
    tier            VARCHAR(20),
    effective_date  DATE NOT NULL,
    expiry_date     DATE,
    is_current      TINYINT(1) DEFAULT 1
);

CREATE TABLE DIM_BRANCH (
    branch_key      INT AUTO_INCREMENT PRIMARY KEY,
    branch_id       VARCHAR(10) NOT NULL,
    branch_name     VARCHAR(100),
    state           VARCHAR(50),
    region          VARCHAR(50)
);

CREATE TABLE DIM_PRODUCT (
    product_key     INT AUTO_INCREMENT PRIMARY KEY,
    product_id      VARCHAR(10) NOT NULL,
    product_name    VARCHAR(100),
    product_type    VARCHAR(50)
);

CREATE TABLE DIM_CHANNEL (
    channel_key     INT AUTO_INCREMENT PRIMARY KEY,
    channel_name    VARCHAR(50),
    txn_type        VARCHAR(50)
);

CREATE TABLE FACT_TRANSACTIONS (
    txn_sk          BIGINT AUTO_INCREMENT PRIMARY KEY,
    txn_id          VARCHAR(20) NOT NULL,
    date_key        INT,
    customer_key    INT,
    branch_key      INT,
    product_key     INT,
    channel_key     INT,
    amount          DECIMAL(18,2),
    balance_after   DECIMAL(18,2),
    txn_hour        TINYINT,
    FOREIGN KEY (date_key)     REFERENCES DIM_DATE(date_key),
    FOREIGN KEY (customer_key) REFERENCES DIM_CUSTOMER(customer_key),
    FOREIGN KEY (branch_key)   REFERENCES DIM_BRANCH(branch_key),
    FOREIGN KEY (product_key)  REFERENCES DIM_PRODUCT(product_key),
    FOREIGN KEY (channel_key)  REFERENCES DIM_CHANNEL(channel_key)
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX idx_fact_date     ON FACT_TRANSACTIONS(date_key);
CREATE INDEX idx_fact_customer ON FACT_TRANSACTIONS(customer_key);
CREATE INDEX idx_fact_branch   ON FACT_TRANSACTIONS(branch_key);
CREATE INDEX idx_fact_product  ON FACT_TRANSACTIONS(product_key);
CREATE INDEX idx_fact_channel  ON FACT_TRANSACTIONS(channel_key);
CREATE INDEX idx_fact_txn_id   ON FACT_TRANSACTIONS(txn_id);

-- ============================================================
-- POPULATE DIM_DATE
-- ============================================================
DROP PROCEDURE IF EXISTS fill_dim_date;

DELIMITER $$
CREATE PROCEDURE fill_dim_date()
BEGIN
    DECLARE v_date DATE DEFAULT '2023-01-01';
    WHILE v_date <= '2024-06-30' DO
        INSERT IGNORE INTO DIM_DATE VALUES (
            DATE_FORMAT(v_date, '%Y%m%d') + 0,
            v_date,
            DAY(v_date),
            DAYNAME(v_date),
            WEEK(v_date),
            MONTH(v_date),
            MONTHNAME(v_date),
            QUARTER(v_date),
            YEAR(v_date),
            IF(DAYOFWEEK(v_date) IN (1,7), 1, 0),
            IF(v_date = LAST_DAY(v_date), 1, 0)
        );
        SET v_date = DATE_ADD(v_date, INTERVAL 1 DAY);
    END WHILE;
END$$
DELIMITER ;

CALL fill_dim_date();

-- ============================================================
-- POPULATE DIMENSIONS FROM RAW TABLE
-- ============================================================

INSERT INTO DIM_BRANCH (branch_id, branch_name, state, region)
SELECT DISTINCT
    Branch_ID,
    Branch_Name,
    State,
    CASE State
        WHEN 'Lagos'  THEN 'South-West'
        WHEN 'Abuja'  THEN 'North-Central'
        WHEN 'Kano'   THEN 'North-West'
        WHEN 'Rivers' THEN 'South-South'
        WHEN 'Ibadan' THEN 'South-West'
        ELSE 'Unknown'
    END
FROM `transaction_data - sheet1`;

INSERT INTO DIM_PRODUCT (product_id, product_name, product_type)
SELECT DISTINCT
    Product_ID,
    Product_Name,
    Product_Type
FROM `transaction_data - sheet1`;

INSERT INTO DIM_CHANNEL (channel_name, txn_type)
SELECT DISTINCT
    Channel,
    Txn_Type
FROM `transaction_data - sheet1`;

DELETE FROM DIM_CHANNEL WHERE channel_name IS NULL;

INSERT INTO DIM_CUSTOMER (customer_id, customer_name, tier, effective_date, expiry_date, is_current)
SELECT DISTINCT
    Customer_ID,
    Customer_Name,
    Tier,
    '2023-01-01',
    NULL,
    1
FROM `transaction_data - sheet1`;

-- ============================================================
-- POPULATE FACT TABLE
-- ============================================================
INSERT INTO FACT_TRANSACTIONS
    (txn_id, date_key, customer_key, branch_key, product_key, channel_key, amount, balance_after, txn_hour)
SELECT
    r.Txn_ID,
    DATE_FORMAT(STR_TO_DATE(r.Txn_Date, '%Y-%m-%d %H:%i:%s'), '%Y%m%d') + 0,
    c.customer_key,
    b.branch_key,
    p.product_key,
    ch.channel_key,
    CAST(REPLACE(r.`Amount (â‚¦)`, ',', '') AS DECIMAL(18,2)),
    CAST(REPLACE(r.`Balance_After (â‚¦)`, ',', '') AS DECIMAL(18,2)),
    HOUR(STR_TO_DATE(r.Txn_Date, '%Y-%m-%d %H:%i:%s'))
FROM `transaction_data - sheet1` r
JOIN DIM_CUSTOMER c  ON c.customer_id   = r.Customer_ID AND c.is_current = 1
JOIN DIM_BRANCH   b  ON b.branch_id     = r.Branch_ID
JOIN DIM_PRODUCT  p  ON p.product_id    = r.Product_ID
JOIN DIM_CHANNEL  ch ON ch.channel_name = r.Channel AND ch.txn_type = r.Txn_Type;

-- ============================================================
-- VERIFY
-- ============================================================
SELECT 'DIM_DATE'           AS table_name, COUNT(*) AS row_count FROM DIM_DATE
UNION ALL
SELECT 'DIM_CUSTOMER',      COUNT(*) FROM DIM_CUSTOMER
UNION ALL
SELECT 'DIM_BRANCH',        COUNT(*) FROM DIM_BRANCH
UNION ALL
SELECT 'DIM_PRODUCT',       COUNT(*) FROM DIM_PRODUCT
UNION ALL
SELECT 'DIM_CHANNEL',       COUNT(*) FROM DIM_CHANNEL
UNION ALL
SELECT 'FACT_TRANSACTIONS', COUNT(*) FROM FACT_TRANSACTIONS;

SET SQL_SAFE_UPDATES = 0;
DELETE FROM DIM_CHANNEL WHERE channel_name IS NULL;
SET SQL_SAFE_UPDATES = 1;

INSERT INTO DIM_CUSTOMER (customer_id, customer_name, tier, effective_date, expiry_date, is_current)
SELECT DISTINCT
    Customer_ID,
    Customer_Name,
    Tier,
    '2023-01-01',
    NULL,
    1
FROM `transaction_data - sheet1`;

INSERT INTO FACT_TRANSACTIONS
    (txn_id, date_key, customer_key, branch_key, product_key, channel_key, amount, balance_after, txn_hour)
SELECT
    r.Txn_ID,
    DATE_FORMAT(STR_TO_DATE(r.Txn_Date, '%Y-%m-%d %H:%i:%s'), '%Y%m%d') + 0,
    c.customer_key,
    b.branch_key,
    p.product_key,
    ch.channel_key,
    CAST(REPLACE(r.`Amount (â‚¦)`, ',', '') AS DECIMAL(18,2)),
    CAST(REPLACE(r.`Balance_After (â‚¦)`, ',', '') AS DECIMAL(18,2)),
    HOUR(STR_TO_DATE(r.Txn_Date, '%Y-%m-%d %H:%i:%s'))
FROM `transaction_data - sheet1` r
JOIN DIM_CUSTOMER c  ON c.customer_id   = r.Customer_ID AND c.is_current = 1
JOIN DIM_BRANCH   b  ON b.branch_id     = r.Branch_ID
JOIN DIM_PRODUCT  p  ON p.product_id    = r.Product_ID
JOIN DIM_CHANNEL  ch ON ch.channel_name = r.Channel AND ch.txn_type = r.Txn_Type;

-- VERIFY
SELECT 'DIM_DATE'           AS table_name, COUNT(*) AS row_count FROM DIM_DATE
UNION ALL
SELECT 'DIM_CUSTOMER',      COUNT(*) FROM DIM_CUSTOMER
UNION ALL
SELECT 'DIM_BRANCH',        COUNT(*) FROM DIM_BRANCH
UNION ALL
SELECT 'DIM_PRODUCT',       COUNT(*) FROM DIM_PRODUCT
UNION ALL
SELECT 'DIM_CHANNEL',       COUNT(*) FROM DIM_CHANNEL
UNION ALL
SELECT 'FACT_TRANSACTIONS', COUNT(*) FROM FACT_TRANSACTIONS;

USE palladium_bank;

-- Fix safe update mode
SET SQL_SAFE_UPDATES = 0;

-- Clean the NULL from channel
DELETE FROM DIM_CHANNEL WHERE channel_name IS NULL;

-- Insert customers
INSERT INTO DIM_CUSTOMER (customer_id, customer_name, tier, effective_date, expiry_date, is_current)
SELECT DISTINCT
    Customer_ID,
    Customer_Name,
    Tier,
    '2023-01-01',
    NULL,
    1
FROM `transaction_data - sheet1`;

-- Insert facts
INSERT INTO FACT_TRANSACTIONS
    (txn_id, date_key, customer_key, branch_key, product_key, channel_key, amount, balance_after, txn_hour)
SELECT
    r.Txn_ID,
    DATE_FORMAT(STR_TO_DATE(r.Txn_Date, '%Y-%m-%d %H:%i:%s'), '%Y%m%d') + 0,
    c.customer_key,
    b.branch_key,
    p.product_key,
    ch.channel_key,
    CAST(REPLACE(r.`Amount (â‚¦)`, ',', '') AS DECIMAL(18,2)),
    CAST(REPLACE(r.`Balance_After (â‚¦)`, ',', '') AS DECIMAL(18,2)),
    HOUR(STR_TO_DATE(r.Txn_Date, '%Y-%m-%d %H:%i:%s'))
FROM `transaction_data - sheet1` r
JOIN DIM_CUSTOMER c  ON c.customer_id   = r.Customer_ID AND c.is_current = 1
JOIN DIM_BRANCH   b  ON b.branch_id     = r.Branch_ID
JOIN DIM_PRODUCT  p  ON p.product_id    = r.Product_ID
JOIN DIM_CHANNEL  ch ON ch.channel_name = r.Channel AND ch.txn_type = r.Txn_Type;

-- Verify
SELECT 'DIM_DATE'           AS table_name, COUNT(*) AS row_count FROM DIM_DATE
UNION ALL
SELECT 'DIM_CUSTOMER',      COUNT(*) FROM DIM_CUSTOMER
UNION ALL
SELECT 'DIM_BRANCH',        COUNT(*) FROM DIM_BRANCH
UNION ALL
SELECT 'DIM_PRODUCT',       COUNT(*) FROM DIM_PRODUCT
UNION ALL
SELECT 'DIM_CHANNEL',       COUNT(*) FROM DIM_CHANNEL
UNION ALL
SELECT 'FACT_TRANSACTIONS', COUNT(*) FROM FACT_TRANSACTIONS;