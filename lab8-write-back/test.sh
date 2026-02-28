#!/bin/bash
# Lab 8: Write-Back Cache 自動化測試腳本
set -e

echo "=========================================="
echo "  Lab 8: Write-Back (Write-Behind) Cache 測試"
echo "=========================================="
echo ""

cd "$(dirname "$0")"
rm -f write_back.db

python3 write_back.py &
SERVER_PID=$!
sleep 1

cleanup() {
    kill $SERVER_PID 2>/dev/null
    rm -f write_back.db
    echo ""
    echo "Server 已停止"
}
trap cleanup EXIT

echo "--- 測試 1: 高速寫入 (僅寫快取, 極低延遲) ---"
echo "寫入 500 次 /homepage:"
START=$(date +%s%N)
for i in $(seq 1 500); do
    curl -s -X POST http://localhost:8085/api/pageview/homepage > /dev/null
done
END=$(date +%s%N)
ELAPSED=$(( (END - START) / 1000000 ))
echo "  500 次寫入耗時: ${ELAPSED}ms (平均: $((ELAPSED / 500))ms/次)"

echo "寫入其他頁面:"
for page in about products contact blog faq; do
    for i in $(seq 1 100); do
        curl -s -X POST http://localhost:8085/api/pageview/$page > /dev/null
    done
done
echo "  每個頁面 100 次, 共 5 個頁面"
echo ""

echo "--- 測試 2: 寫入後立即檢查 (DB 應為空!) ---"
RESP=$(curl -s http://localhost:8085/api/stats)
DIRTY=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['dirty_keys_count'])")
DB_STATE=$(echo "$RESP" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['db_state']))")
echo "  dirty_keys (未同步): $DIRTY"
echo "  DB 中的記錄數: $DB_STATE"
if [ "$DIRTY" -gt 0 ]; then
    echo "PASS: 資料尚在快取中, DB 尚未同步 (Write-Back 特性)"
fi
echo ""

echo "--- 測試 3: 比較快取與 DB 的差異 ---"
curl -s http://localhost:8085/api/compare | python3 -m json.tool
echo ""

echo "--- 測試 4: 等待背景同步 (5 秒間隔) ---"
echo "等待 7 秒讓背景程序同步..."
sleep 7

echo "同步後狀態:"
RESP=$(curl -s http://localhost:8085/api/stats)
DIRTY=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['dirty_keys_count'])")
FLUSHES=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['flush_count'])")
FLUSHED=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['items_flushed'])")
echo "  dirty_keys: $DIRTY (應為 0)"
echo "  flush 次數: $FLUSHES"
echo "  已同步項目: $FLUSHED"
if [ "$DIRTY" = "0" ]; then
    echo "PASS: 所有資料已同步到 DB"
fi
echo ""

echo "--- 測試 5: 同步後一致性檢查 ---"
COMPARE=$(curl -s http://localhost:8085/api/compare)
echo "$COMPARE" | python3 -m json.tool
INCONSISTENT=$(echo "$COMPARE" | python3 -c "import sys,json; print(json.load(sys.stdin)['inconsistent_keys'])")
if [ "$INCONSISTENT" = "0" ]; then
    echo "PASS: 同步後 Cache 與 DB 完全一致"
fi
echo ""

echo "--- 測試 6: 展示 dirty window (資料遺失風險視窗) ---"
echo "新增寫入 (同步剛完成, 開始新的 dirty window):"
curl -s -X POST http://localhost:8085/api/pageview/new-page > /dev/null
curl -s -X POST http://localhost:8085/api/pageview/new-page > /dev/null
curl -s -X POST http://localhost:8085/api/pageview/new-page > /dev/null

RESP=$(curl -s http://localhost:8085/api/stats)
RISK=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['data_loss_risk_keys'])")
echo "  有遺失風險的 keys: $RISK"
echo "  (如果此刻 server 崩潰, 這些資料會遺失)"

echo "等待同步..."
sleep 6
RESP=$(curl -s http://localhost:8085/api/stats)
RISK=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['data_loss_risk_keys'])")
echo "  同步後風險 keys: $RISK (應為空)"
echo ""

echo "--- 測試 7: 單次寫入延遲 vs Write-Through 比較 ---"
RESP=$(curl -s -X POST http://localhost:8085/api/pageview/latency-test)
WB_MS=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['write_time_ms'])")
echo "  Write-Back  單次寫入: ${WB_MS}ms (僅寫記憶體)"
echo "  Write-Through 參考值: ~5-7ms (需寫 DB)"
echo "  Write-Back 快了數十倍！但有資料遺失風險"
echo ""

echo "--- 測試 8: 最終統計 ---"
curl -s http://localhost:8085/api/stats | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'  總寫入次數: {d[\"total_writes\"]}')
print(f'  背景同步次數: {d[\"flush_count\"]}')
print(f'  已同步項目數: {d[\"items_flushed\"]}')
print(f'  最後同步時間: {d[\"last_flush_at\"]}')
print(f'  當前 dirty keys: {d[\"dirty_keys_count\"]}')
"
echo ""

echo "=========================================="
echo "  Lab 8 Write-Back Cache 測試完成！"
echo "=========================================="
echo ""
echo "核心學習:"
echo "  - Write-Back: 寫入極快 (~0.05ms), 但有 dirty window"
echo "  - Write-Through: 寫入較慢 (~5ms), 但保證一致性"
echo "  - 選擇取決於: 你能容忍多少資料遺失?"
