#!/bin/bash
# Lab 2: CDN Cache 自動化測試腳本
set -e

echo "=========================================="
echo "  Lab 2: CDN Cache 測試"
echo "=========================================="
echo ""

cd "$(dirname "$0")"

# 啟動服務
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
echo "--- 測試 1: 首次請求 (應為 MISS, 延遲較高) ---"
START=$(date +%s%N)
HEADERS=$(curl -sI http://localhost:8081/api/exchange-rate)
END=$(date +%s%N)
ELAPSED=$(( (END - START) / 1000000 ))
echo "$HEADERS" | grep -iE '(HTTP|X-Cache|X-Edge|X-Served)'
echo "回應時間: ${ELAPSED}ms"
CACHE_STATUS=$(echo "$HEADERS" | grep -i 'X-Cache-Status' | tr -d '\r' | awk '{print $2}')
if [ "$CACHE_STATUS" = "MISS" ]; then
    echo "PASS: 首次請求為 MISS (回源取得)"
else
    echo "INFO: 首次狀態為 $CACHE_STATUS"
fi
echo ""

echo "--- 測試 2: 第二次請求 (應為 HIT, 延遲極低) ---"
START=$(date +%s%N)
HEADERS=$(curl -sI http://localhost:8081/api/exchange-rate)
END=$(date +%s%N)
ELAPSED=$(( (END - START) / 1000000 ))
echo "$HEADERS" | grep -iE '(HTTP|X-Cache|X-Edge)'
echo "回應時間: ${ELAPSED}ms"
CACHE_STATUS=$(echo "$HEADERS" | grep -i 'X-Cache-Status' | tr -d '\r' | awk '{print $2}')
if [ "$CACHE_STATUS" = "HIT" ]; then
    echo "PASS: 第二次請求為 HIT (從邊緣快取回應)"
else
    echo "INFO: 狀態為 $CACHE_STATUS"
fi
echo ""

echo "--- 測試 3: 連續 10 次請求, 觀察源站實際收到幾次 ---"
for i in $(seq 1 10); do
    curl -s http://localhost:8081/api/exchange-rate > /dev/null
done
echo "源站日誌 (應只有 1 次回源):"
docker compose logs origin 2>&1 | grep "ORIGIN" | tail -5
echo ""

echo "--- 測試 4: 不同路徑是獨立快取 ---"
echo "請求 /api/exchange-rate:"
curl -sI http://localhost:8081/api/exchange-rate | grep -i 'X-Cache-Status' | tr -d '\r'
echo "請求 /api/product-image (新路徑，應為 MISS):"
curl -sI http://localhost:8081/api/product-image | grep -i 'X-Cache-Status' | tr -d '\r'
echo "再次請求 /api/product-image (應為 HIT):"
curl -sI http://localhost:8081/api/product-image | grep -i 'X-Cache-Status' | tr -d '\r'
echo ""

echo "--- 測試 5: 等待 TTL 過期 (15 秒) ---"
echo "等待 17 秒..."
sleep 17
START=$(date +%s%N)
HEADERS=$(curl -sI http://localhost:8081/api/exchange-rate)
END=$(date +%s%N)
ELAPSED=$(( (END - START) / 1000000 ))
CACHE_STATUS=$(echo "$HEADERS" | grep -i 'X-Cache-Status' | tr -d '\r' | awk '{print $2}')
echo "TTL 過期後狀態: $CACHE_STATUS"
echo "回應時間: ${ELAPSED}ms"
if [ "$CACHE_STATUS" = "MISS" ] || [ "$CACHE_STATUS" = "EXPIRED" ]; then
    echo "PASS: TTL 過期後重新回源"
fi
echo ""

echo "--- 測試 6: 驗證快取內容一致性 ---"
BODY1=$(curl -s http://localhost:8081/api/exchange-rate)
sleep 1
BODY2=$(curl -s http://localhost:8081/api/exchange-rate)
TS1=$(echo "$BODY1" | python3 -c "import sys,json; print(json.load(sys.stdin)['timestamp'])")
TS2=$(echo "$BODY2" | python3 -c "import sys,json; print(json.load(sys.stdin)['timestamp'])")
echo "第一次 timestamp: $TS1"
echo "第二次 timestamp: $TS2"
if [ "$TS1" = "$TS2" ]; then
    echo "PASS: 快取命中時回傳相同的 timestamp (內容一致)"
else
    echo "INFO: timestamp 不同 (可能快取已過期)"
fi
echo ""

echo "=========================================="
echo "  Lab 2 CDN Cache 測試完成！"
echo "=========================================="
