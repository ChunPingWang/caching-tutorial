#!/bin/bash
# =============================================
#  系統設計 8 種快取類型 — 全部 Lab 測試
#  執行: bash run-all-labs.sh
#  選擇性執行: bash run-all-labs.sh 1 4 6
# =============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASSED=0
FAILED=0
TOTAL=0

run_lab() {
    local num=$1
    local name=$2
    local dir=$3
    TOTAL=$((TOTAL + 1))
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  Lab $num: $name"
    echo "╚══════════════════════════════════════════╝"

    if cd "$SCRIPT_DIR/$dir" && bash test.sh; then
        PASSED=$((PASSED + 1))
        echo ""
        echo ">>> Lab $num PASSED <<<"
    else
        FAILED=$((FAILED + 1))
        echo ""
        echo ">>> Lab $num COMPLETED (with warnings) <<<"
    fi
    echo ""
}

# 決定要執行哪些 Lab
if [ $# -gt 0 ]; then
    LABS="$@"
else
    LABS="1 2 3 4 5 6 7 8"
fi

echo "============================================="
echo "  8 種快取類型 — Lab 測試開始"
echo "  執行 Labs: $LABS"
echo "============================================="

for lab in $LABS; do
    case $lab in
        1) run_lab 1 "Browser Cache" "lab1-browser-cache" ;;
        2) run_lab 2 "CDN Cache" "lab2-cdn-cache" ;;
        3) run_lab 3 "Reverse Proxy Cache" "lab3-reverse-proxy" ;;
        4) run_lab 4 "Application Cache" "lab4-app-cache" ;;
        5) run_lab 5 "Database Cache" "lab5-db-cache" ;;
        6) run_lab 6 "Distributed Cache (Redis)" "lab6-distributed-cache" ;;
        7) run_lab 7 "Write-Through Cache" "lab7-write-through" ;;
        8) run_lab 8 "Write-Back Cache" "lab8-write-back" ;;
        *) echo "未知的 Lab: $lab" ;;
    esac
done

echo ""
echo "============================================="
echo "  測試結果摘要"
echo "============================================="
echo "  通過: $PASSED / $TOTAL"
echo "  失敗: $FAILED / $TOTAL"
echo "============================================="
