USE cache_lab;

CREATE TABLE products (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100),
    price DECIMAL(10,2),
    category VARCHAR(50),
    description TEXT,
    INDEX idx_category (category),
    INDEX idx_price (price)
) ENGINE=InnoDB;

-- 插入 10000 筆測試資料
DELIMITER //
CREATE PROCEDURE generate_data()
BEGIN
    DECLARE i INT DEFAULT 1;
    WHILE i <= 10000 DO
        INSERT INTO products (name, price, category, description)
        VALUES (
            CONCAT('Product-', i),
            ROUND(RAND() * 10000, 2),
            ELT(1 + FLOOR(RAND() * 5), 'Electronics', 'Clothing', 'Food', 'Books', 'Sports'),
            CONCAT('Description for product ', i, '. This is a sample product for testing database caching behavior.')
        );
        SET i = i + 1;
    END WHILE;
END //
DELIMITER ;

CALL generate_data();
DROP PROCEDURE generate_data;
