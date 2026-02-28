#!/bin/bash
# Lab 7: Write-Through Cache 自動化測試腳本
set -e

echo "=========================================="
echo "  Lab 7: Write-Through Cache 測試"
echo "=========================================="
echo ""

cd "$(dirname "$0")"
rm -f write_through.db

python3 write_through.py &
SERVER_PID=$!
sleep 1

cleanup() {
    kill $SERVER_PID 2>/dev/null
    rm -f write_through.db
    echo ""
    echo "Server 已停止"
}
trap cleanup EXIT

echo "--- 測試 1: Write-Through 寫入 ---"
echo "寫入帳戶 ACC001 (Alice, 50000):"
curl -s -X POST http://localhost:8084/api/account \
  -H "Content-Type: application/json" \
  -d '{"id":"ACC001","name":"Alice","balance":50000}' | python3 -m json.tool

echo "寫入帳戶 ACC002 (Bob, 30000):"
curl -s -X POST http://localhost:8084/api/account \
  -H "Content-Type: application/json" \
  -d '{"id":"ACC002","name":"Bob","balance":30000}' | python3 -m json.tool

echo "寫入帳戶 ACC003 (Carol, 75000):"
curl -s -X POST http://localhost:8084/api/account \
  -H "Content-Type: application/json" \
  -d '{"id":"ACC003","name":"Carol","balance":75000}' | python3 -m json.tool
echo ""

echo "--- 測試 2: 讀取 (應來自 Cache) ---"
RESP=$(curl -s http://localhost:8084/api/account/ACC001)
echo "$RESP" | python3 -m json.tool
SOURCE=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['source'])")
if [ "$SOURCE" = "cache" ]; then
    echo "PASS: 讀取來自 Cache (Write-Through 寫入後快取已更新)"
fi
echo ""

echo "--- 測試 3: Cache 與 DB 一致性驗證 ---"
VERIFY=$(curl -s http://localhost:8084/api/verify)
echo "$VERIFY" | python3 -m json.tool
CONSISTENT=$(echo "$VERIFY" | python3 -c "import sys,json; print(json.load(sys.stdin)['cache_db_consistent'])")
if [ "$CONSISTENT" = "True" ]; then
    echo "PASS: Cache 與 DB 完全一致！"
fi
echo ""

echo "--- 測試 4: 更新後一致性 ---"
echo "更新 ACC001 餘額: 50000 -> 42000"
curl -s -X POST http://localhost:8084/api/account \
  -H "Content-Type: application/json" \
  -d '{"id":"ACC001","name":"Alice","balance":42000}' > /dev/null

echo "讀取更新後的 ACC001:"
RESP=$(curl -s http://localhost:8084/api/account/ACC001)
BALANCE=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['balance'])")
echo "  balance: $BALANCE"
if [ "$BALANCE" = "42000" ]; then
    echo "PASS: 餘額立即更新為 42000"
fi

echo "驗證一致性:"
curl -s http://localhost:8084/api/verify | python3 -c "
import sys,json
d = json.load(sys.stdin)
print(f'  consistent: {d[\"cache_db_consistent\"]}')
print(f'  db_records: {d[\"db_records\"]}')
print(f'  cache_records: {d[\"cache_records\"]}')
"
echo ""

echo "--- 測試 5: 多次寫入 + 讀取的命中率 ---"
# 寫入 10 個帳戶
for i in $(seq 10 19); do
    curl -s -X POST http://localhost:8084/api/account \
      -H "Content-Type: application/json" \
      -d "{\"id\":\"ACC0$i\",\"name\":\"User-$i\",\"balance\":$((i * 1000))}" > /dev/null
done
# 讀取 (全部應為 HIT)
for i in $(seq 10 19); do
    curl -s http://localhost:8084/api/account/ACC0$i > /dev/null
done

echo "統計資料:"
curl -s http://localhost:8084/api/stats | python3 -m json.tool
echo ""

echo "--- 測試 6: 最終一致性驗證 ---"
VERIFY=$(curl -s http://localhost:8084/api/verify)
echo "$VERIFY" | python3 -m json.tool
CONSISTENT=$(echo "$VERIFY" | python3 -c "import sys,json; print(json.load(sys.stdin)['cache_db_consistent'])")
if [ "$CONSISTENT" = "True" ]; then
    echo "PASS: 所有操作後, Cache 與 DB 始終一致！"
    echo "      這就是 Write-Through 的核心優勢: 強一致性"
fi
echo ""

echo "=========================================="
echo "  Lab 7 Write-Through Cache 測試完成！"
echo "=========================================="
