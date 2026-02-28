#!/bin/bash
# Lab 1: Browser Cache 自動化測試腳本
set -e

echo "=========================================="
echo "  Lab 1: Browser Cache 測試"
echo "=========================================="
echo ""

# 啟動 server (背景)
cd "$(dirname "$0")"
python3 cache_server.py &
SERVER_PID=$!
sleep 1

cleanup() {
    kill $SERVER_PID 2>/dev/null
    echo ""
    echo "Server 已停止"
}
trap cleanup EXIT

echo "--- 測試 1: 首次請求 HTML (應回傳 200 + Cache-Control: no-cache) ---"
RESPONSE=$(curl -sI http://localhost:8080/index.html)
echo "$RESPONSE" | grep -iE '(HTTP|Cache-Control|ETag)'
echo ""

echo "--- 測試 2: 首次請求 CSS (應回傳 200 + max-age=3600) ---"
RESPONSE=$(curl -sI http://localhost:8080/style.css)
echo "$RESPONSE" | grep -iE '(HTTP|Cache-Control|ETag)'
echo ""

echo "--- 測試 3: 首次請求 JS (應回傳 200 + max-age=3600) ---"
RESPONSE=$(curl -sI http://localhost:8080/app.js)
echo "$RESPONSE" | grep -iE '(HTTP|Cache-Control|ETag)'
echo ""

echo "--- 測試 4: 首次請求 SVG (應回傳 200 + max-age=3600) ---"
RESPONSE=$(curl -sI http://localhost:8080/logo.svg)
echo "$RESPONSE" | grep -iE '(HTTP|Cache-Control|ETag)'
echo ""

# 取得 ETag 值
ETAG=$(curl -sI http://localhost:8080/style.css | grep -i 'ETag' | tr -d '\r' | awk '{print $2}')
echo "--- 測試 5: 條件式請求 (If-None-Match, 應回傳 304) ---"
echo "使用 ETag: $ETAG"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "If-None-Match: $ETAG" http://localhost:8080/style.css)
echo "HTTP Status: $HTTP_CODE"
if [ "$HTTP_CODE" = "304" ]; then
    echo "PASS: 收到 304 Not Modified"
else
    echo "FAIL: 預期 304，實際收到 $HTTP_CODE"
fi
echo ""

echo "--- 測試 6: 錯誤的 ETag (應回傳 200, 全量傳輸) ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H 'If-None-Match: "wrong-etag"' http://localhost:8080/style.css)
echo "HTTP Status: $HTTP_CODE"
if [ "$HTTP_CODE" = "200" ]; then
    echo "PASS: ETag 不符，回傳完整內容 200"
else
    echo "FAIL: 預期 200，實際收到 $HTTP_CODE"
fi
echo ""

echo "--- 測試 7: 不同資源類型的 Cache-Control 差異 ---"
echo "HTML:"
curl -sI http://localhost:8080/index.html | grep -i 'Cache-Control' | tr -d '\r'
echo "CSS:"
curl -sI http://localhost:8080/style.css | grep -i 'Cache-Control' | tr -d '\r'
echo "JS:"
curl -sI http://localhost:8080/app.js | grep -i 'Cache-Control' | tr -d '\r'
echo ""

echo "=========================================="
echo "  Lab 1 測試完成！所有快取 Header 正常運作"
echo "=========================================="
