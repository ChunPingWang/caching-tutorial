# 系統設計中的 8 種快取類型 — 完整實作教學

> 你可能認為「快取 = Redis」，但在真實的系統設計中，快取是一個**多層堆疊（Caching Stack）**，從瀏覽器到資料庫，每一層解決不同問題、以不同方式失效。

本教學包含 **8 個可在本機執行的 Lab**，每個 Lab 都有自動化測試腳本，讓你親手驗證每種快取的行為。

---

## 目錄

- [前置準備](#前置準備)
- [快取層級總覽](#快取層級總覽)
- [為什麼需要理解多層快取？](#為什麼需要理解多層快取)
- [Lab 1：Browser Cache（瀏覽器快取）](#lab-1browser-cache瀏覽器快取)
- [Lab 2：CDN Cache（內容傳遞網路快取）](#lab-2cdn-cache內容傳遞網路快取)
- [Lab 3：Reverse Proxy Cache（反向代理快取）](#lab-3reverse-proxy-cache反向代理快取)
- [Lab 4：Application Cache（應用程式快取）](#lab-4application-cache應用程式快取)
- [Lab 5：Database Cache（資料庫快取）](#lab-5database-cache資料庫快取)
- [Lab 6：Distributed Cache（分散式快取）](#lab-6distributed-cache分散式快取)
- [Lab 7：Write-Through Cache（寫穿快取）](#lab-7write-through-cache寫穿快取)
- [Lab 8：Write-Back Cache（寫回快取）](#lab-8write-back-cache寫回快取)
- [快取策略決策矩陣](#快取策略決策矩陣)
- [企業架構中的快取設計原則](#企業架構中的快取設計原則)
- [常見面試問題](#常見面試問題)

---

## 前置準備

### 必要工具

```bash
# Docker (Lab 2, 3, 5, 6 需要)
docker --version        # 需要 20.10+
docker compose version  # 需要 v2+

# Python 3 (Lab 1, 4, 7, 8 需要)
python3 --version       # 需要 3.8+

# curl (所有 Lab 驗證都用到)
curl --version
```

### 快速驗證所有 Lab

```bash
# 執行全部 8 個 Lab 測試
bash run-all-labs.sh

# 選擇性執行 (例如只跑 Lab 1 和 Lab 4)
bash run-all-labs.sh 1 4

# 單獨執行某個 Lab
cd lab1-browser-cache && bash test.sh
```

### 專案結構

```
caching-tutorial/
├── README.md                          # 本教學文件
├── 8-types-of-caching-in-system-design.md  # 參考文件
├── run-all-labs.sh                    # 一鍵執行所有 Lab
├── lab1-browser-cache/                # Lab 1: 瀏覽器快取
│   ├── cache_server.py                #   HTTP Server (含 Cache-Control/ETag)
│   ├── index.html, style.css, app.js  #   測試用靜態資源
│   └── test.sh                        #   自動化測試
├── lab2-cdn-cache/                    # Lab 2: CDN 邊緣快取
│   ├── origin_server.py               #   源站 Server
│   ├── nginx-cdn.conf                 #   NGINX 邊緣快取配置
│   ├── docker-compose.yml             #   Docker 服務定義
│   └── test.sh
├── lab3-reverse-proxy/                # Lab 3: 反向代理快取
│   ├── backend.py                     #   後端 API Server
│   ├── nginx.conf                     #   NGINX 代理快取配置
│   ├── docker-compose.yml
│   └── test.sh
├── lab4-app-cache/                    # Lab 4: 應用程式快取
│   ├── app_cache_demo.py              #   LRU Cache + HTTP Server
│   └── test.sh
├── lab5-db-cache/                     # Lab 5: 資料庫快取
│   ├── init.sql                       #   MySQL 初始化 (10000 筆資料)
│   ├── docker-compose.yml
│   └── test.sh
├── lab6-distributed-cache/            # Lab 6: Redis 分散式快取
│   ├── docker-compose.yml
│   └── test.sh
├── lab7-write-through/                # Lab 7: Write-Through 策略
│   ├── write_through.py               #   同步寫入 Cache + DB
│   └── test.sh
└── lab8-write-back/                   # Lab 8: Write-Back 策略
    ├── write_back.py                  #   非同步批次同步
    └── test.sh
```

---

## 快取層級總覽

一個請求從用戶端到資料庫，可能經過 4~5 層快取：

```
用戶端 ──► [1] Browser Cache         (瀏覽器本地)
   │
   ▼
[2] CDN Cache                        (全球邊緣節點)
   │
   ▼
[3] Reverse Proxy Cache              (NGINX / Varnish)
   │
   ▼
[4] Application Cache                (應用程式記憶體)
   │
   ▼
[6] Distributed Cache                (Redis / Memcached 叢集)
   │
   ▼
[5] Database Cache                   (DB Buffer Pool)
   │
   ▼
資料庫 (持久化儲存)

寫入策略橫跨多層:
  [7] Write-Through ──► Cache + DB 同步寫入
  [8] Write-Back    ──► Cache 先寫, DB 非同步追趕
```

---

## 為什麼需要理解多層快取？

在企業級系統中，每一層快取都有其設計取捨（trade-off）：

| 取捨維度 | 越靠近用戶端 | 越靠近資料庫 |
|---------|:---:|:---:|
| **延遲** | 極低 (微秒~毫秒) | 較高 (毫秒~百毫秒) |
| **資料新鮮度** | 難保證 | 容易保證 |
| **命中率** | 取決於使用者行為 | 取決於查詢模式 |
| **共享性** | 單一用戶 | 所有服務共享 |

### 什麼時候「不應該」用快取？

- **寫入頻率 >> 讀取頻率**：快取頻繁失效，反而增加開銷
- **資料必須 100% 即時**：金融交易的即時報價
- **資料量極小**：直接查資料庫就夠快
- **每次查詢都不同**：快取命中率趨近零

---

## Lab 1：Browser Cache（瀏覽器快取）

### 你會學到什麼

- `Cache-Control` Header 的不同指令 (`max-age`, `no-cache`, `no-store`)
- `ETag` 條件式請求與 `304 Not Modified`
- 不同資源類型的快取策略差異

### 核心概念

| 項目 | 說明 |
|------|------|
| **所在位置** | 用戶的瀏覽器 |
| **快取內容** | HTML、CSS、JS、圖片、字型 |
| **核心價值** | 重複造訪時幾乎零延遲 |

**工作原理：**

```
第一次造訪:
  瀏覽器 ──GET /style.css──► Server
  瀏覽器 ◄──200 OK + Cache-Control: max-age=3600 + ETag: "abc"── Server

第二次造訪 (3600秒內):
  瀏覽器 ──(不發請求, 直接用本地快取)──

第二次造訪 (3600秒後):
  瀏覽器 ──GET /style.css + If-None-Match: "abc"──► Server
  瀏覽器 ◄──304 Not Modified (不傳內容, 省流量)── Server
```

### 執行與驗證

```bash
cd lab1-browser-cache
bash test.sh
```

### 已驗證的測試結果

```
--- 測試 1: HTML 回傳 no-cache ---
Cache-Control: no-cache            # HTML 每次都重新驗證
ETag: "0c1cb6ef..."

--- 測試 2: CSS 回傳 max-age=3600 ---
Cache-Control: public, max-age=3600  # 靜態資源快取 1 小時
ETag: "b9903edf..."

--- 測試 5: 條件式請求 (應回傳 304) ---
HTTP Status: 304                   # PASS: ETag 比對成功, 不重傳內容

--- 測試 6: 錯誤的 ETag (應回傳 200) ---
HTTP Status: 200                   # PASS: ETag 不符, 回傳完整內容
```

### Cache-Control 常用指令速查

| 指令 | 意義 | 適用場景 |
|------|------|---------|
| `public, max-age=31536000, immutable` | 快取一年，不可變 | 帶 hash 的 JS/CSS |
| `no-cache` | 每次都要跟 server 確認 | HTML 入口頁 |
| `no-store` | 完全不快取 | 含敏感資料的 API |
| `private, max-age=0, must-revalidate` | 不快取在共享快取中 | 個人化 API 回應 |

### 適用場景

- 銀行網銀前端靜態資源（logo、CSS framework）
- 電商網站商品圖片縮圖
- 企業 SPA 應用靜態檔案

---

## Lab 2：CDN Cache（內容傳遞網路快取）

### 你會學到什麼

- CDN 邊緣節點如何快取內容
- `MISS` → `HIT` → `EXPIRED` 的狀態轉換
- TTL 過期與回源機制

### 核心概念

| 項目 | 說明 |
|------|------|
| **所在位置** | 全球邊緣節點（Edge Locations） |
| **快取內容** | 圖片、JS/CSS、影片、靜態頁面 |
| **核心價值** | 地理位置就近回應，降低延遲並保護源站 |

**工作原理：**

```
第一次請求 (MISS):
  用戶 ──► CDN 邊緣節點 ──(回源)──► 源站
       ◄── 回應 + 快取一份 ◄────── 回應

第二次請求 (HIT):
  用戶 ──► CDN 邊緣節點 ──(直接回應, 不回源)
       ◄── 從快取回應 (超快！)

TTL 過期後 (EXPIRED):
  用戶 ──► CDN 邊緣節點 ──(重新回源)──► 源站
```

### 執行與驗證

```bash
cd lab2-cdn-cache
bash test.sh
```

### 已驗證的測試結果

```
--- 測試 1: 首次請求 (MISS, 回源) ---
X-Cache-Status: MISS
X-Edge-Location: TW-TPE-01
回應時間: 508ms                    # 包含 500ms 源站延遲

--- 測試 2: 第二次請求 (HIT, 邊緣回應) ---
X-Cache-Status: HIT
回應時間: 6ms                      # 快了 85 倍！

--- 測試 4: 不同路徑獨立快取 ---
/api/exchange-rate: HIT
/api/product-image: MISS          # 新路徑, 需回源
/api/product-image: HIT           # 第二次命中

--- 測試 5: TTL 過期 (15秒) ---
X-Cache-Status: EXPIRED           # TTL 到期, 重新回源
回應時間: 509ms                    # 重新包含源站延遲
```

### CDN 快取的關鍵指標

| 指標 | 說明 | 目標 |
|------|------|------|
| **Cache Hit Ratio** | 命中率 | > 90% |
| **Time to First Byte** | 首位元組延遲 | HIT < 50ms |
| **Origin Requests** | 回源請求數 | 越少越好 |

---

## Lab 3：Reverse Proxy Cache（反向代理快取）

### 你會學到什麼

- NGINX 如何作為 API 的快取層
- 壓力測試下快取的保護效果
- 不同 URL 路徑的獨立快取
- `BYPASS` 設定讓特定路徑不快取

### 核心概念

| 項目 | 說明 |
|------|------|
| **所在位置** | 客戶端與後端服務之間 |
| **快取內容** | API 回應、HTML 頁面 |
| **核心價值** | 減輕後端負載、加速 API 交付 |

### 執行與驗證

```bash
cd lab3-reverse-proxy
bash test.sh
```

### 已驗證的測試結果

```
--- 測試 3: 壓力測試 — 50 個請求 ---
壓測前後端已處理: 4 個請求
壓測後後端已處理: 5 個請求
50 個請求中，穿透到後端的: 1 個
PASS: 快取有效擋下了 49/50 個請求   # 98% 的請求不需要後端處理！

--- 測試 4: 不同 URL 獨立快取 ---
/api/v1/product/1: MISS → HIT
/api/v1/product/2: MISS → HIT      # 每個 URL 有自己的快取

--- 測試 5: 健康檢查不快取 ---
X-Cache-Status: BYPASS              # 指定路徑跳過快取
```

### NGINX 快取配置範例

```nginx
# 定義快取區域
proxy_cache_path /var/cache/nginx levels=1:2
    keys_zone=api_cache:10m     # 快取 metadata 記憶體 10MB
    max_size=1g                 # 快取檔案最大 1GB
    inactive=60m;               # 60 分鐘無人存取則移除

location /api/v1/products {
    proxy_cache api_cache;
    proxy_cache_valid 200 5m;   # 200 回應快取 5 分鐘
    proxy_cache_valid 404 1m;   # 404 回應快取 1 分鐘
    proxy_cache_key "$scheme$request_method$host$request_uri";
    add_header X-Cache-Status $upstream_cache_status always;
    proxy_pass http://backend;
}
```

---

## Lab 4：Application Cache（應用程式快取）

### 你會學到什麼

- LRU (Least Recently Used) 淘汰策略的運作
- TTL 過期機制
- 快取容量限制與淘汰行為
- 命中率的計算與意義

### 核心概念

| 項目 | 說明 |
|------|------|
| **所在位置** | 服務/應用程式層內部 |
| **快取內容** | 計算結果、用戶 Session、高頻查詢結果 |
| **核心價值** | 避免重複計算，本地記憶體讀取在微秒等級 |

**LRU 淘汰策略圖解：**

```
容量=5 的 LRU Cache:

初始: [A] [B] [C] [D] [E]   (容量已滿)
                              ↑最久未用  ↑最近使用

讀取 B: [A] [C] [D] [E] [B]  (B 移到最近位置)

新增 F: [C] [D] [E] [B] [F]  (A 被淘汰, F 加入)
         ↑A 被淘汰了！
```

### 執行與驗證

```bash
cd lab4-app-cache
bash test.sh
```

### 已驗證的測試結果

```
--- 測試 1: Cache MISS (首次查詢) ---
cache_hit: false
response_time_ms: 500.23           # 包含 500ms DB 查詢

--- 測試 2: Cache HIT (重複查詢) ---
cache_hit: true
response_time_ms: 0.01             # 快了 50000 倍！

--- 測試 3: LRU 淘汰 (容量=5) ---
存入 product 1~5: cached_keys: [1, 2, 3, 4, 5]
存入 product 6:   cached_keys: [2, 3, 4, 5, 6]
                   evictions: 1    # product:1 被 LRU 淘汰

--- 測試 5: TTL 過期 (15秒) ---
立即查詢: cache_hit=True
16秒後: cache_hit=False            # TTL 過期

--- 測試 6: 命中率 ---
hits: 9, misses: 3
hit_ratio: 75.0%                   # 3次 MISS + 9次 HIT
```

### Spring Boot 實作參考

```java
@Service
public class ProductService {
    @Cacheable(value = "products", key = "#productId",
               unless = "#result == null")
    public Product getProduct(String productId) {
        return productRepository.findById(productId)
            .orElseThrow(() -> new ProductNotFoundException(productId));
    }

    @CacheEvict(value = "products", key = "#product.id")
    public Product updateProduct(Product product) {
        return productRepository.save(product);
    }
}
```

---

## Lab 5：Database Cache（資料庫快取）

### 你會學到什麼

- InnoDB Buffer Pool 如何將熱點資料保留在記憶體中
- Buffer Pool 命中率的計算方式
- 索引快取如何加速查詢
- `EXPLAIN` 分析查詢是否使用索引

### 核心概念

| 項目 | 說明 |
|------|------|
| **所在位置** | 資料庫引擎內部 |
| **快取內容** | 資料頁、索引頁 |
| **核心價值** | 減少磁碟 I/O，加速重複讀取 |

**Buffer Pool 工作原理：**

```
查詢 SELECT * FROM products WHERE id = 1

第一次查詢:
  MySQL ──► 檢查 Buffer Pool ──(未命中)──► 從磁碟讀取
       ◄── 返回資料 + 存入 Buffer Pool ◄──

第二次相同查詢:
  MySQL ──► 檢查 Buffer Pool ──(命中！)──► 直接返回
                                           (不需要磁碟 I/O)
```

### 執行與驗證

```bash
cd lab5-db-cache
bash test.sh
```

### 已驗證的測試結果

```
--- 測試 3: 聚合查詢 ---
category     | count | avg_price | max_price
Electronics  |   125 |  4856.91  | 9988.09
Clothing     |   120 |  4891.43  | 9805.81
Food         |   126 |  4461.20  | 9768.59

--- 測試 4: 重複 10 次查詢 ---
Buffer Pool 邏輯讀取: 444259 -> 451241 (增加 6982)
磁碟物理讀取: 865 -> 865 (增加 0)     # 零磁碟 I/O！全部從記憶體讀取

--- 測試 5: Buffer Pool 命中率 ---
Buffer Pool Hit Ratio: 99.81%       # 超過 99% 目標

--- 測試 6: EXPLAIN 比較 ---
無索引 (全表掃描): type=ALL, rows=1091
有索引 (idx_category): type=ref, rows=229   # 掃描行數減少 79%
```

### Buffer Pool 調優建議

```sql
-- 計算命中率
-- Hit Ratio = 1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests)
-- 目標 > 99%

-- Buffer Pool 大小通常設為可用記憶體的 70-80%
SET GLOBAL innodb_buffer_pool_size = 8589934592; -- 8GB
```

---

## Lab 6：Distributed Cache（分散式快取）

### 你會學到什麼

- Redis 五大資料結構的實際應用
- TTL 自動過期機制
- Pipeline 批量操作效能
- 命中率統計與記憶體管理
- Pub/Sub 快取失效通知

### 核心概念

| 項目 | 說明 |
|------|------|
| **所在位置** | 獨立的共享快取叢集 |
| **快取內容** | 跨服務共享的資料 |
| **核心價值** | 微服務架構中的共享狀態管理 |

**Redis 資料結構速查：**

| 結構 | 命令 | 應用場景 |
|------|------|---------|
| **String** | `SET/GET` | 商品快取、計數器 |
| **Hash** | `HSET/HGET` | Session、用戶 Profile |
| **List** | `LPUSH/LRANGE` | 最近瀏覽、訊息佇列 |
| **Set** | `SADD/SMEMBERS` | 標籤、共同好友 |
| **Sorted Set** | `ZADD/ZRANGE` | 排行榜、延遲佇列 |

### 執行與驗證

```bash
cd lab6-distributed-cache
bash test.sh
```

### 已驗證的測試結果

```
--- 測試 2: String (商品快取) ---
GET product:1001 -> {"name":"MacBook","price":59900}
TTL: 60s

--- 測試 3: Hash (Session) ---
user_id: 42, username: alice, role: admin

--- 測試 4: List (最近瀏覽, 只保留 3 筆) ---
Product-E, Product-D, Product-C

--- 測試 5: Sorted Set (排行榜 Top 3) ---
Dave: 3100, Bob: 2300, Carol: 1800

--- 測試 6: TTL 過期 ---
立即讀取: expires-soon
4秒後: (nil)                       # 自動過期刪除

--- 測試 7: Pipeline 批量寫入 ---
1000 個 key, errors: 0, 耗時: 88ms  # 平均 0.088ms/key

--- 測試 8: 命中率 ---
keyspace_hits: 100, misses: 20
命中率: ~83%

--- 測試 9: 記憶體配置 ---
已使用: 1.12M, 上限: 50.00M
淘汰策略: allkeys-lru

--- 測試 10: Pub/Sub 快取失效 ---
channel: cache:invalidate
message: {"key":"product:1001","reason":"price_updated"}
```

### Redis 架構選型指南

| 模式 | 適用場景 | 特點 |
|------|---------|------|
| **Standalone** | 開發/測試環境 | 簡單，無高可用 |
| **Sentinel** | 中小規模生產環境 | 自動故障轉移，讀寫分離 |
| **Cluster** | 大規模生產環境 | 資料分片，水平擴展 |

---

## Lab 7：Write-Through Cache（寫穿快取）

### 你會學到什麼

- Write-Through 如何保證 Cache 與 DB 的強一致性
- 寫入同時更新兩邊的代價與好處
- 何時選擇 Write-Through

### 核心概念

| 項目 | 說明 |
|------|------|
| **運作方式** | 同時寫入快取與資料庫 |
| **最適場景** | 強一致性需求 |
| **核心價值** | 低過期資料風險，讀取始終快速 |

**流程圖：**

```
寫入請求
   │
   ├──► 1. 寫入 DB ───► 成功 ✓
   │
   └──► 2. 寫入 Cache ─► 成功 ✓
   │
   ▼
回應客戶端（兩者都成功才回應）

讀取請求
   │
   ▼
檢查 Cache ──(命中)──► 直接回應 (極快)
         └──(未命中)──► 查 DB → 回填 Cache → 回應
```

### 執行與驗證

```bash
cd lab7-write-through
bash test.sh
```

### 已驗證的測試結果

```
--- 測試 1: Write-Through 寫入 ---
strategy: write-through
write_time_ms: 7.25                # 需等 DB 寫入完成

--- 測試 2: 讀取來源 ---
source: cache                      # 寫入後直接從 Cache 讀取
read_time_ms: 0.0153               # 極快

--- 測試 3: 一致性驗證 ---
cache_db_consistent: true          # Cache 與 DB 完全一致！
db_records: 3, cache_records: 3

--- 測試 4: 更新後一致性 ---
更新 ACC001: 50000 -> 42000
讀取 balance: 42000                # 立即生效
cache_db_consistent: true          # 更新後依然一致

--- 測試 5: 命中率 ---
hits: 12, misses: 0
hit_ratio: 100.0%                  # Write-Through 寫入後全部命中

--- 測試 6: 13 筆操作後一致性 ---
cache_db_consistent: true          # 始終一致！
mismatches: []
```

### 適用場景

- **銀行帳戶餘額**：餘額必須即時正確
- **庫存數量**：電商即時庫存必須準確
- **用戶權限設定**：安全相關變更必須立即生效

---

## Lab 8：Write-Back Cache（寫回快取）

### 你會學到什麼

- Write-Back 如何實現極低寫入延遲
- 「Dirty Window」（資料遺失風險視窗）的概念
- 非同步批次同步的實作
- Write-Back vs Write-Through 的延遲對比

### 核心概念

| 項目 | 說明 |
|------|------|
| **運作方式** | 先寫入快取，稍後非同步寫入資料庫 |
| **最適場景** | 高寫入量、對延遲敏感的系統 |
| **核心價值** | 極快的寫入速度 |

**流程圖：**

```
寫入請求
   │
   ▼
寫入 Cache ──► 立即回應客戶端 (超快！)
   │
   ▼ (背景非同步, 每 5 秒)
批次寫入 DB
   │
   ▼
確認持久化 ──► 清除 dirty 標記

⚠️ Dirty Window: 寫入 Cache 到同步 DB 之間的時間
   如果此時 server 崩潰, dirty 資料會遺失！
```

### 執行與驗證

```bash
cd lab8-write-back
bash test.sh
```

### 已驗證的測試結果

```
--- 測試 1: 高速寫入 ---
500 次寫入耗時: 2006ms (平均: 4ms/次)  # 每次只寫記憶體

--- 測試 2: 寫入後立即檢查 ---
dirty_keys: 1                       # 有未同步的資料！
DB 中的記錄數: 6                     # 部分已由之前的 flush 同步

--- 測試 3: Cache 與 DB 差異 ---
inconsistent_keys: 1
  faq: cache=100, db=75             # Cache 超前, DB 落後

--- 測試 4: 等待背景同步 (7秒) ---
dirty_keys: 0                       # 全部同步完成！
flush 次數: 2

--- 測試 5: 同步後一致性 ---
inconsistent_keys: 0                # 同步後完全一致

--- 測試 6: Dirty Window 展示 ---
寫入後 risk_keys: ['new-page']      # 此刻崩潰會遺失這個 key
同步後 risk_keys: []                 # 同步後無風險

--- 測試 7: 延遲對比 ---
Write-Back:    0.0057ms             # 僅寫記憶體
Write-Through: ~5-7ms              # 需等 DB (慢 1000 倍)
```

### 適用場景

- **頁面瀏覽計數器**：高頻寫入，少量遺失可接受
- **IoT 感測器數據**：大量寫入，允許批次處理
- **用戶行為日誌**：點擊流、瀏覽記錄等分析數據

---

## 快取策略決策矩陣

### 寫入策略比較

| 維度 | Write-Through | Write-Back | Cache-Aside |
|------|:---:|:---:|:---:|
| **寫入延遲** | 高 (~5-7ms) | 極低 (~0.005ms) | 中 |
| **讀取延遲** | 低 | 低 | 首次高，後續低 |
| **資料一致性** | 強一致 | 最終一致 | 最終一致 |
| **資料遺失風險** | 極低 | 中～高 | 低 |
| **實作複雜度** | 低 | 高 | 中 |
| **適用場景** | 金融交易 | 日誌/計數器 | 通用查詢 |

### 如何選擇快取層？

```
你的資料是靜態的嗎？
  ├── 是 → Browser Cache + CDN Cache
  └── 否 → 讀取頻率高嗎？
              ├── 是 → 多服務共享嗎？
              │         ├── 是 → Distributed Cache (Redis)
              │         └── 否 → Application Cache (本地)
              └── 否 → Database Cache 就足夠
```

### 8 種快取類型總表

| # | 類型 | 位置 | 延遲 | 核心場景 | 本教學 Lab |
|---|------|------|------|---------|-----------|
| 1 | Browser Cache | 瀏覽器 | ~0ms | 靜態資源零延遲 | Lab 1 |
| 2 | CDN Cache | 邊緣節點 | ~5ms | 就近回應、保護源站 | Lab 2 |
| 3 | Reverse Proxy | NGINX | ~1ms | 減輕後端負載 | Lab 3 |
| 4 | Application Cache | App 記憶體 | ~0.01ms | 避免重複計算 | Lab 4 |
| 5 | Database Cache | DB 引擎 | ~0.1ms | 減少磁碟 I/O | Lab 5 |
| 6 | Distributed Cache | Redis 叢集 | ~1ms | 微服務共享狀態 | Lab 6 |
| 7 | Write-Through | 跨層策略 | 寫慢讀快 | 強一致性寫入 | Lab 7 |
| 8 | Write-Back | 跨層策略 | 寫超快 | 高速寫入 | Lab 8 |

---

## 企業架構中的快取設計原則

### 1. 分層思考（Think in Layers）

不要只在單一層級加快取。關鍵是確定每一層快取的**職責邊界**。

### 2. 失效策略優先（Invalidation First）

設計快取時先想清楚「怎麼讓它過期」。Cache invalidation 是電腦科學中公認的兩大難題之一。

> "There are only two hard things in Computer Science: cache invalidation and naming things."
> — Phil Karlton

### 3. 監控與可觀測性（Observability）

| 指標 | 說明 | 目標 |
|------|------|------|
| Hit Ratio | 命中率 | > 90% |
| Latency P99 | 99 百分位延遲 | < 10ms |
| Memory Usage | 記憶體使用量 | < 80% capacity |
| Eviction Count | 淘汰次數 | 趨勢穩定 |

### 4. 優雅降級（Graceful Degradation）

快取層失效時，系統應能降級到下一層，而非直接崩潰。

```
Redis 斷線?
  ├── Circuit Breaker 觸發
  ├── 降級到 DB 直接查詢
  └── 記錄告警, 自動恢復後重新啟用快取
```

### 5. 安全性考量（Security）

- 快取中的敏感資料（Session Token、個資）需要加密
- 設定適當的 TTL，避免過期 Session 殘留
- 使用 `Cache-Control: private` 防止共享快取洩漏個人資料

---

## 常見面試問題

### Q1: 什麼是 Cache Stampede（快取雪崩）？如何防止？

當大量快取同時過期，所有請求穿透到 DB，造成 DB 崩潰。

**解法：**
- **TTL 加隨機值**：避免同時過期
- **互斥鎖 (Mutex)**：只允許一個請求回源
- **預先更新**：TTL 快到期時提前刷新

### Q2: Cache-Aside vs Read-Through 有什麼區別？

| | Cache-Aside | Read-Through |
|---|---|---|
| 快取管理者 | 應用程式自己 | 快取框架/庫 |
| 程式碼侵入性 | 高（需手動讀寫快取） | 低（透明代理） |
| 靈活性 | 高 | 中 |

### Q3: 如何保證 Cache 與 DB 的一致性？

- **Write-Through**：同步寫入，強一致
- **Write-Back + WAL**：先寫日誌再非同步同步
- **Cache-Aside + TTL**：最終一致，靠 TTL 兜底
- **事件驅動**：DB 變更觸發 Cache 失效（如 CDC + Kafka）

### Q4: Redis 和 Memcached 怎麼選？

| | Redis | Memcached |
|---|---|---|
| 資料結構 | 豐富（String/Hash/List/Set/ZSet） | 只有 String |
| 持久化 | 支援（RDB/AOF） | 不支援 |
| 叢集模式 | Redis Cluster | 客戶端分片 |
| Pub/Sub | 支援 | 不支援 |
| 多執行緒 | 單執行緒 + I/O 多工 | 多執行緒 |
| 選擇建議 | 通用首選 | 純 Key-Value 且要多核效能 |

---

## 全部清理

```bash
# 清理所有 Docker 資源 (如果有殘留)
cd lab2-cdn-cache && docker compose down 2>/dev/null; cd ..
cd lab3-reverse-proxy && docker compose down 2>/dev/null; cd ..
cd lab5-db-cache && docker compose down -v 2>/dev/null; cd ..
cd lab6-distributed-cache && docker compose down 2>/dev/null; cd ..

# 清理 SQLite 檔案
rm -f lab7-write-through/write_through.db
rm -f lab8-write-back/write_back.db
```

---

## 參考資料

- 基於 Rocky Bhatia 的「8 Types of Caching Used in System Design」整理、擴充與實作
- [Redis 官方文件](https://redis.io/docs/)
- [NGINX Caching Guide](https://docs.nginx.com/nginx/admin-guide/content-cache/content-caching/)
- [MDN: HTTP Caching](https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching)

---

*每個 Lab 都經過自動化測試驗證，可隨時透過 `bash test.sh` 重新執行。*
