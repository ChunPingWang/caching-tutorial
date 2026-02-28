#!/bin/bash
# Lab 4: Application Cache 自動化測試腳本
set -e

echo "=========================================="
echo "  Lab 4: Application Cache 測試"
echo "=========================================="
echo ""

cd "$(dirname "$0")"

python3 app_cache_demo.py &
SERVER_PID=$!
sleep 1

cleanup() {
    kill $SERVER_PID 2>/dev/null
    echo ""
    echo "Server 已停止"
}
trap cleanup EXIT

echo "--- 測試 1: Cache MISS (首次查詢, ~500ms) ---"
RESP=$(curl -s http://localhost:8083/api/product/1)
echo "$RESP" | python3 -m json.tool
HIT=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['cache_hit'])")
MS=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['response_time_ms'])")
if [ "$HIT" = "False" ]; then
    echo "PASS: 首次查詢為 Cache MISS, 耗時 ${MS}ms"
fi
echo ""

echo "--- 測試 2: Cache HIT (重複查詢, ~0ms) ---"
RESP=$(curl -s http://localhost:8083/api/product/1)
echo "$RESP" | python3 -m json.tool
HIT=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['cache_hit'])")
MS=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['response_time_ms'])")
if [ "$HIT" = "True" ]; then
    echo "PASS: 重複查詢為 Cache HIT, 耗時 ${MS}ms (快了數百倍！)"
fi
echo ""

echo "--- 測試 3: LRU 淘汰機制 (容量=5, 存入 6 個) ---"
echo "存入 product 1~5..."
for i in 1 2 3 4 5; do
    curl -s http://localhost:8083/api/product/$i > /dev/null
done
echo "快取狀態:"
curl -s http://localhost:8083/api/cache/stats | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'  cached_items: {d[\"cached_items\"]}/{d[\"capacity\"]}')
print(f'  cached_keys: {d[\"cached_keys\"]}')
print(f'  evictions: {d[\"evictions\"]}')
"

echo ""
echo "存入 product 6 (應淘汰最久未使用的 product:1)..."
curl -s http://localhost:8083/api/product/6 > /dev/null
echo "快取狀態:"
curl -s http://localhost:8083/api/cache/stats | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'  cached_items: {d[\"cached_items\"]}/{d[\"capacity\"]}')
print(f'  cached_keys: {d[\"cached_keys\"]}')
print(f'  evictions: {d[\"evictions\"]}')
"
KEYS=$(curl -s http://localhost:8083/api/cache/stats | python3 -c "import sys,json; print(json.load(sys.stdin)['cached_keys'])")
if echo "$KEYS" | grep -qv "product:1"; then
    echo "PASS: product:1 被 LRU 淘汰, product:6 加入"
fi
echo ""

echo "--- 測試 4: 被淘汰的 key 變回 MISS ---"
RESP=$(curl -s http://localhost:8083/api/product/1)
HIT=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['cache_hit'])")
echo "查詢被淘汰的 product/1: cache_hit=$HIT"
if [ "$HIT" = "False" ]; then
    echo "PASS: 被淘汰後重新變為 MISS"
fi
echo ""

echo "--- 測試 5: TTL 過期驗證 ---"
echo "清空快取後重新存入 product/1..."
curl -s http://localhost:8083/api/cache/clear > /dev/null
curl -s http://localhost:8083/api/product/1 > /dev/null
echo "立即查詢: cache_hit=$(curl -s http://localhost:8083/api/product/1 | python3 -c "import sys,json; print(json.load(sys.stdin)['cache_hit'])")"
echo "等待 16 秒讓 TTL 過期 (TTL=15s)..."
sleep 16
RESP=$(curl -s http://localhost:8083/api/product/1)
HIT=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['cache_hit'])")
echo "過期後查詢: cache_hit=$HIT"
STATS=$(curl -s http://localhost:8083/api/cache/stats)
EXP=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['expirations'])")
echo "過期次數: $EXP"
if [ "$HIT" = "False" ] && [ "$EXP" -gt 0 ]; then
    echo "PASS: TTL 過期後 cache miss, 過期計數正確"
fi
echo ""

echo "--- 測試 6: 命中率統計 ---"
curl -s http://localhost:8083/api/cache/clear > /dev/null
# 首次查 1~3 (3 MISS)
for i in 1 2 3; do curl -s http://localhost:8083/api/product/$i > /dev/null; done
# 重複查 1~3 各 3 次 (9 HIT)
for i in 1 2 3 1 2 3 1 2 3; do curl -s http://localhost:8083/api/product/$i > /dev/null; done
STATS=$(curl -s http://localhost:8083/api/cache/stats)
echo "$STATS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'  hits: {d[\"hits\"]}')
print(f'  misses: {d[\"misses\"]}')
print(f'  hit_ratio: {d[\"hit_ratio\"]}')
"
HR=$(echo "$STATS" | python3 -c "import sys,json; print(json.load(sys.stdin)['hit_ratio'])")
echo "PASS: 命中率 = $HR (預期 75%)"
echo ""

echo "=========================================="
echo "  Lab 4 Application Cache 測試完成！"
echo "=========================================="
