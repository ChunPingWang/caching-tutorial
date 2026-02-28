#!/bin/bash
# Lab 5: Database Cache 自動化測試腳本
set -e

echo "=========================================="
echo "  Lab 5: Database Cache (InnoDB Buffer Pool) 測試"
echo "=========================================="
echo ""

cd "$(dirname "$0")"

echo "啟動 MySQL..."
docker compose up -d 2>&1

MYSQL="docker compose exec -T mysql mysql -uroot -prootpass cache_lab"

echo "等待 MySQL 就緒 (初始化 10000 筆資料)..."
for i in $(seq 1 30); do
    if docker compose exec -T mysql mysql -uroot -prootpass -e "SELECT 1" 2>/dev/null | grep -q 1; then
        break
    fi
    sleep 2
    echo "  等待中... ($i)"
done
# 確認資料已建立
COUNT=$($MYSQL -sN -e "SELECT COUNT(*) FROM products" 2>/dev/null)
echo "資料筆數: $COUNT"
echo ""

cleanup() {
    echo ""
    echo "清理 Docker 服務..."
    docker compose down -v 2>&1
    echo "清理完成"
}
trap cleanup EXIT

echo "--- 測試 1: Buffer Pool 基本狀態 ---"
$MYSQL -e "
SELECT
  VARIABLE_NAME, VARIABLE_VALUE
FROM performance_schema.global_status
WHERE VARIABLE_NAME IN (
  'Innodb_buffer_pool_read_requests',
  'Innodb_buffer_pool_reads',
  'Innodb_buffer_pool_pages_data',
  'Innodb_buffer_pool_pages_total'
)
ORDER BY VARIABLE_NAME;
" 2>/dev/null
echo ""

echo "--- 測試 2: 記錄查詢前的讀取統計 ---"
BEFORE_REQUESTS=$($MYSQL -sN -e "SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Innodb_buffer_pool_read_requests'" 2>/dev/null)
BEFORE_READS=$($MYSQL -sN -e "SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Innodb_buffer_pool_reads'" 2>/dev/null)
echo "  Buffer Pool 邏輯讀取: $BEFORE_REQUESTS"
echo "  磁碟物理讀取: $BEFORE_READS"
echo ""

echo "--- 測試 3: 執行聚合查詢 ---"
echo "查詢: 按類別統計平均價格"
$MYSQL -e "
SELECT category, COUNT(*) as count, ROUND(AVG(price),2) as avg_price, ROUND(MAX(price),2) as max_price
FROM products
GROUP BY category
ORDER BY count DESC;
" 2>/dev/null
echo ""

echo "--- 測試 4: 重複執行 10 次相同查詢, 觀察 Buffer Pool 效果 ---"
for i in $(seq 1 10); do
    $MYSQL -sN -e "SELECT * FROM products WHERE category = 'Electronics' LIMIT 10;" 2>/dev/null > /dev/null
done
echo "10 次查詢完成"

AFTER_REQUESTS=$($MYSQL -sN -e "SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Innodb_buffer_pool_read_requests'" 2>/dev/null)
AFTER_READS=$($MYSQL -sN -e "SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Innodb_buffer_pool_reads'" 2>/dev/null)
echo "  Buffer Pool 邏輯讀取: $BEFORE_REQUESTS -> $AFTER_REQUESTS (增加 $((AFTER_REQUESTS - BEFORE_REQUESTS)))"
echo "  磁碟物理讀取: $BEFORE_READS -> $AFTER_READS (增加 $((AFTER_READS - BEFORE_READS)))"
echo ""

echo "--- 測試 5: Buffer Pool 命中率計算 ---"
$MYSQL -e "
SELECT
  ROUND(
    (1 - (
      (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads')
      /
      NULLIF((SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests'), 0)
    )) * 100, 4
  ) AS 'Buffer Pool Hit Ratio (%)';
" 2>/dev/null
echo "目標: > 99%"
echo ""

echo "--- 測試 6: 索引快取效果 (使用 EXPLAIN) ---"
echo "無索引的查詢 (全表掃描):"
$MYSQL -e "EXPLAIN SELECT * FROM products WHERE description LIKE '%testing%' LIMIT 5;" 2>/dev/null
echo ""
echo "有索引的查詢 (使用 idx_category):"
$MYSQL -e "EXPLAIN SELECT * FROM products WHERE category = 'Electronics' LIMIT 5;" 2>/dev/null
echo ""

echo "--- 測試 7: Buffer Pool 大小資訊 ---"
$MYSQL -e "
SELECT
  @@innodb_buffer_pool_size / 1024 / 1024 AS 'Buffer Pool Size (MB)',
  (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_data') AS 'Data Pages',
  (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_free') AS 'Free Pages',
  (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_total') AS 'Total Pages';
" 2>/dev/null
echo ""

echo "=========================================="
echo "  Lab 5 Database Cache 測試完成！"
echo "=========================================="
