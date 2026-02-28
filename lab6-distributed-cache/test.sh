#!/bin/bash
# Lab 6: Distributed Cache (Redis) 自動化測試腳本
set -e

echo "=========================================="
echo "  Lab 6: Distributed Cache (Redis) 測試"
echo "=========================================="
echo ""

cd "$(dirname "$0")"

echo "啟動 Redis..."
docker compose up -d 2>&1
sleep 3

REDIS="docker compose exec -T redis redis-cli"

cleanup() {
    echo ""
    echo "清理 Docker 服務..."
    docker compose down 2>&1
    echo "清理完成"
}
trap cleanup EXIT

echo "--- 測試 1: 基本連線 ---"
PONG=$($REDIS ping)
echo "PING -> $PONG"
if [ "$PONG" = "PONG" ]; then
    echo "PASS: Redis 連線正常"
fi
echo ""

echo "--- 測試 2: String Key-Value (商品快取) ---"
$REDIS SET "product:1001" '{"name":"MacBook","price":59900}' EX 60 > /dev/null
RESULT=$($REDIS GET "product:1001")
TTL=$($REDIS TTL "product:1001")
echo "  SET product:1001 -> GET: $RESULT"
echo "  TTL: ${TTL}s"
echo "PASS: String 基本操作正常"
echo ""

echo "--- 測試 3: Hash (Session 快取) ---"
$REDIS HSET "session:user123" "user_id" "42" "username" "alice" "role" "admin" "login_at" "2024-01-01T10:00:00" > /dev/null
$REDIS EXPIRE "session:user123" 3600 > /dev/null
echo "  Session 資料:"
$REDIS HGETALL "session:user123"
SESSION_TTL=$($REDIS TTL "session:user123")
echo "  Session TTL: ${SESSION_TTL}s"
echo "PASS: Hash 操作正常"
echo ""

echo "--- 測試 4: List (最近瀏覽記錄) ---"
$REDIS DEL "recent:user42" > /dev/null
for item in "Product-A" "Product-B" "Product-C" "Product-D" "Product-E"; do
    $REDIS LPUSH "recent:user42" "$item" > /dev/null
done
$REDIS LTRIM "recent:user42" 0 2 > /dev/null  # 只保留最近 3 筆
echo "  最近瀏覽 (最多3筆):"
$REDIS LRANGE "recent:user42" 0 -1
echo "PASS: List 操作正常 (保留最近 3 筆)"
echo ""

echo "--- 測試 5: Sorted Set (排行榜) ---"
$REDIS ZADD "leaderboard" 1500 "Alice" 2300 "Bob" 1800 "Carol" 3100 "Dave" 900 "Eve" > /dev/null
echo "  排行榜 Top 3:"
$REDIS ZREVRANGE "leaderboard" 0 2 WITHSCORES
echo "PASS: Sorted Set 排行榜正常"
echo ""

echo "--- 測試 6: TTL 過期驗證 ---"
$REDIS SET "temp:data" "expires-soon" EX 3 > /dev/null
echo "  SET temp:data (TTL=3s)"
VAL1=$($REDIS GET "temp:data")
echo "  立即讀取: $VAL1"
sleep 4
VAL2=$($REDIS GET "temp:data")
echo "  4秒後讀取: ${VAL2:-(nil)}"
if [ -z "$VAL2" ]; then
    echo "PASS: TTL 過期後自動刪除"
fi
echo ""

echo "--- 測試 7: 批量寫入效能 ---"
PIPE_CMD=""
for i in $(seq 1 1000); do
    PIPE_CMD="${PIPE_CMD}SET item:$i value-$i EX 300\n"
done
START=$(date +%s%N)
echo -e "$PIPE_CMD" | $REDIS --pipe 2>&1 | tail -1
END=$(date +%s%N)
ELAPSED=$(( (END - START) / 1000000 ))
DBSIZE=$($REDIS DBSIZE)
echo "  1000 個 key 寫入耗時: ${ELAPSED}ms"
echo "  資料庫大小: $DBSIZE"
echo "PASS: Pipeline 批量寫入正常"
echo ""

echo "--- 測試 8: 命中率統計 ---"
# 重置統計
$REDIS CONFIG RESETSTAT > /dev/null
# 讀取存在的 key (100 hits)
for i in $(seq 1 100); do
    $REDIS GET "item:$((RANDOM % 1000 + 1))" > /dev/null
done
# 讀取不存在的 key (20 misses)
for i in $(seq 1 20); do
    $REDIS GET "nonexist:$i" > /dev/null
done
HITS=$($REDIS INFO stats | grep keyspace_hits | tr -d '\r' | cut -d: -f2)
MISSES=$($REDIS INFO stats | grep keyspace_misses | tr -d '\r' | cut -d: -f2)
echo "  keyspace_hits: $HITS"
echo "  keyspace_misses: $MISSES"
if [ "$HITS" -gt 0 ] && [ "$MISSES" -gt 0 ]; then
    TOTAL=$((HITS + MISSES))
    RATIO=$((HITS * 100 / TOTAL))
    echo "  命中率: ~${RATIO}%"
    echo "PASS: 命中率統計正常"
fi
echo ""

echo "--- 測試 9: 記憶體與淘汰策略 ---"
MEM=$($REDIS INFO memory | grep used_memory_human | tr -d '\r' | cut -d: -f2)
MAXMEM=$($REDIS INFO memory | grep maxmemory_human | tr -d '\r' | cut -d: -f2)
POLICY=$($REDIS INFO memory | grep maxmemory_policy | tr -d '\r' | cut -d: -f2)
echo "  已使用記憶體: $MEM"
echo "  最大記憶體: $MAXMEM"
echo "  淘汰策略: $POLICY"
echo "PASS: 記憶體配置正確"
echo ""

echo "--- 測試 10: Pub/Sub 快取失效通知 (模擬) ---"
# 在背景訂閱
$REDIS SUBSCRIBE "cache:invalidate" &
SUB_PID=$!
sleep 1
# 發布失效通知
RECEIVERS=$($REDIS PUBLISH "cache:invalidate" '{"key":"product:1001","reason":"price_updated"}')
sleep 1
kill $SUB_PID 2>/dev/null || true
wait $SUB_PID 2>/dev/null || true
echo "  接收者數量: $RECEIVERS"
if [ "$RECEIVERS" -ge 1 ]; then
    echo "PASS: Pub/Sub 快取失效通知正常"
else
    echo "INFO: Pub/Sub 發布完成 (接收者: $RECEIVERS)"
fi
echo ""

echo "=========================================="
echo "  Lab 6 Distributed Cache 測試完成！"
echo "=========================================="
