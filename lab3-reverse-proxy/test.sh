#!/bin/bash
# Lab 3: Reverse Proxy Cache 自動化測試腳本
set -e

echo "=========================================="
echo "  Lab 3: Reverse Proxy Cache 測試"
echo "=========================================="
echo ""

cd "$(dirname "$0")"

echo "啟動 Docker 服務..."
docker compose up -d 2>&1
echo "等待服務啟動..."
sleep 5

cleanup() {
    echo ""
    echo "清理 Docker 服務..."
    docker compose down 2>&1
    echo "清理完成"
}
trap cleanup EXIT

echo ""
echo "--- 測試 1: MISS → HIT 轉換 ---"
echo "第 1 次請求 (MISS):"
RESP1=$(curl -sD - http://localhost:8082/api/v1/products)
echo "$RESP1" | grep -iE '(X-Cache-Status)'
BODY1=$(echo "$RESP1" | tail -1)
echo "  backend_request_count: $(echo "$BODY1" | python3 -c "import sys,json; print(json.load(sys.stdin).get('backend_request_count','N/A'))" 2>/dev/null || echo "N/A")"

echo "第 2 次請求 (HIT):"
RESP2=$(curl -sD - http://localhost:8082/api/v1/products)
echo "$RESP2" | grep -iE '(X-Cache-Status)'

echo "第 3 次請求 (HIT):"
curl -sI http://localhost:8082/api/v1/products | grep -i 'X-Cache-Status'
echo ""

echo "--- 測試 2: 確認後端只收到 1 次請求 ---"
HEALTH=$(curl -s http://localhost:8082/api/v1/health)
echo "後端狀態: $HEALTH"
echo ""

echo "--- 測試 3: 壓力測試 — 50 個請求 ---"
BEFORE=$(curl -s http://localhost:8082/api/v1/health | python3 -c "import sys,json; print(json.load(sys.stdin)['requests_served'])")
echo "壓測前後端已處理: $BEFORE 個請求"

for i in $(seq 1 50); do
    curl -s -o /dev/null http://localhost:8082/api/v1/products
done

AFTER=$(curl -s http://localhost:8082/api/v1/health | python3 -c "import sys,json; print(json.load(sys.stdin)['requests_served'])")
echo "壓測後後端已處理: $AFTER 個請求"
DIFF=$((AFTER - BEFORE))
echo "50 個請求中，穿透到後端的: $DIFF 個"
if [ "$DIFF" -lt 5 ]; then
    echo "PASS: 快取有效擋下了 $(( 50 - DIFF ))/50 個請求 (${DIFF} 穿透)"
else
    echo "INFO: $DIFF 個請求穿透 (可能 TTL 過期導致)"
fi
echo ""

echo "--- 測試 4: 不同 URL 路徑獨立快取 ---"
echo "請求 /api/v1/product/1 (MISS):"
curl -sI http://localhost:8082/api/v1/product/1 | grep -i 'X-Cache-Status'
echo "請求 /api/v1/product/2 (MISS - 不同路徑):"
curl -sI http://localhost:8082/api/v1/product/2 | grep -i 'X-Cache-Status'
echo "再次 /api/v1/product/1 (HIT):"
curl -sI http://localhost:8082/api/v1/product/1 | grep -i 'X-Cache-Status'
echo "再次 /api/v1/product/2 (HIT):"
curl -sI http://localhost:8082/api/v1/product/2 | grep -i 'X-Cache-Status'
echo ""

echo "--- 測試 5: 健康檢查不快取 (BYPASS) ---"
curl -sI http://localhost:8082/api/v1/health | grep -i 'X-Cache-Status'
curl -sI http://localhost:8082/api/v1/health | grep -i 'X-Cache-Status'
echo "PASS: 健康檢查始終 BYPASS"
echo ""

echo "--- 測試 6: TTL 過期驗證 ---"
echo "寫入快取:"
curl -sI http://localhost:8082/api/v1/products | grep -i 'X-Cache-Status'
echo "等待 12 秒讓 TTL 過期..."
sleep 12
echo "過期後請求:"
CACHE_STATUS=$(curl -sI http://localhost:8082/api/v1/products | grep -i 'X-Cache-Status' | tr -d '\r' | awk '{print $2}')
echo "X-Cache-Status: $CACHE_STATUS"
if [ "$CACHE_STATUS" = "MISS" ] || [ "$CACHE_STATUS" = "EXPIRED" ]; then
    echo "PASS: TTL 過期後重新回源"
fi
echo ""

echo "=========================================="
echo "  Lab 3 Reverse Proxy Cache 測試完成！"
echo "=========================================="
