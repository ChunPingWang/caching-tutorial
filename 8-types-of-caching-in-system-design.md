# 系統設計中的 8 種快取類型 — 完整教學指南

> 你可能認為「快取 = Redis」，但在真實的系統設計中，快取是一個**多層堆疊（Caching Stack）**，而非單一元件。不同的快取存在於不同位置、解決不同問題、也以不同方式失效。

---

## 為什麼需要理解多層快取？

在企業級系統中（銀行核心系統、零售電商平台、製造業 ERP），一個請求從用戶端到資料庫可能經過 4～5 層快取。每一層都有其設計取捨（trade-off）：

- **延遲 vs. 一致性**：越靠近用戶端，延遲越低，但資料新鮮度越難保證。
- **命中率 vs. 記憶體成本**：快取越多資料，命中率越高，但記憶體與管理成本也越高。
- **寫入速度 vs. 資料持久性**：Write-Back 寫入飛快，但若節點崩潰，未落盤的資料可能遺失。

掌握這 8 種快取類型，你就能設計出**高效能、可擴展、且在高負載下依然穩定**的系統。

---

## 快取層級總覽

```
用戶端 ──► Browser Cache
   │
   ▼
CDN Cache（全球邊緣節點）
   │
   ▼
Reverse Proxy Cache（NGINX / Varnish）
   │
   ▼
Application Cache（應用程式內部）
   │
   ▼
Distributed Cache（Redis / Memcached 叢集）
   │
   ▼
Database Cache（DB Buffer Pool / Query Cache）
   │
   ▼
資料庫（持久化儲存）
```

> 寫入策略（Write-Through / Write-Back）橫跨多個層級，決定資料如何從快取同步到持久化儲存。

---

## 1. Browser Cache（瀏覽器快取）

### 定位

| 項目 | 說明 |
|------|------|
| **所在位置** | 用戶的瀏覽器 |
| **快取內容** | 靜態前端資源（HTML、CSS、JS、圖片、字型） |
| **核心價值** | 重複造訪時幾乎零延遲 |

### 關鍵元素

- **Cache-Control Headers**：透過 `max-age`、`no-cache`、`no-store` 等指令控制快取行為。
- **ETag / If-None-Match**：條件式請求，伺服器回傳 304 Not Modified 時不重傳內容。
- **Local Storage Caching**：將不常變動的資料（如用戶偏好設定）存放於 `localStorage`。
- **Service Worker Cache**：PWA 架構下的離線快取策略，攔截 fetch 請求。
- **Hard vs. Soft Refresh**：Hard refresh（Ctrl+Shift+R）略過快取；Soft refresh 仍使用快取。
- **Stale Assets Risk**：版本更新後用戶可能看到舊版資源，需搭配 cache-busting 策略（如檔名加 hash）。

### 實務建議

```
# 典型的 Cache-Control 設定
# 靜態資源（帶 hash 的 JS/CSS）
Cache-Control: public, max-age=31536000, immutable

# HTML 入口頁面
Cache-Control: no-cache

# API 回應
Cache-Control: private, max-age=0, must-revalidate
```

### 適用場景

- 銀行網銀前端的靜態資源（logo、CSS framework）
- 電商網站的商品圖片縮圖
- 企業內部系統的 SPA 應用靜態檔案

---

## 2. CDN Cache（內容傳遞網路快取）

### 定位

| 項目 | 說明 |
|------|------|
| **所在位置** | 全球邊緣節點（Edge Locations） |
| **快取內容** | 圖片、JS/CSS、影片、靜態頁面 |
| **核心價值** | 地理位置就近回應，降低延遲並保護源站 |

### 關鍵元素

- **Edge Caching**：將內容複製到靠近用戶的邊緣節點。
- **Geo-based Delivery**：根據用戶地理位置路由到最近的 PoP（Point of Presence）。
- **TTL Settings**：控制邊緣節點快取的存活時間。
- **Origin Shielding**：在 CDN 與源站之間加一層 Shield 節點，減少回源請求。
- **Cache Invalidation**：內容更新時主動清除 CDN 快取（最困難的部分之一）。
- **Signed URLs**：為敏感資源產生有時效性的存取連結。
- **Purge by URL**：針對特定 URL 立即清除快取。
- **Cache Hit Ratio**：衡量 CDN 效能的核心指標，目標通常 > 90%。

### 實務建議

- 對於金融業的公開資訊頁面（匯率、利率公告），TTL 可設短（如 60 秒）以確保資料新鮮。
- 電商的商品圖片可設較長 TTL（24 小時），搭配版本化 URL 處理更新。
- 使用 Origin Shielding 可大幅降低源站負載，特別是在促銷活動的流量高峰期。

---

## 3. Reverse Proxy Cache（反向代理快取）

### 定位

| 項目 | 說明 |
|------|------|
| **所在位置** | 客戶端與後端服務之間 |
| **快取內容** | API 回應、HTML 頁面 |
| **核心價值** | 減輕後端負載、加速 API 交付 |

### 關鍵元素

- **NGINX / Varnish Caching**：最常見的反向代理快取實作。
- **Response Caching Rules**：依據 HTTP 狀態碼、Header、URL pattern 決定是否快取。
- **Cache Key Design**：精心設計快取鍵（URL + Query Params + Headers），避免快取汙染。
- **Rate Limiting Support**：在代理層實作限流，保護下游服務。
- **Compression Support**：Gzip / Brotli 壓縮，減少傳輸量。
- **SSL Termination**：在代理層終止 TLS，降低後端加解密開銷。
- **Load Reduction**：對於高頻且結果穩定的 API，快取可減少 70%+ 的後端請求。

### 實務建議

```nginx
# NGINX 反向代理快取配置範例
proxy_cache_path /var/cache/nginx levels=1:2
    keys_zone=api_cache:10m max_size=1g inactive=60m;

location /api/v1/products {
    proxy_cache api_cache;
    proxy_cache_valid 200 5m;
    proxy_cache_valid 404 1m;
    proxy_cache_key "$scheme$request_method$host$request_uri";
    proxy_pass http://backend;
}
```

### 適用場景

- 銀行的公開 API Gateway（匯率查詢、分行資訊）
- 零售業的商品目錄 API
- 製造業的設備狀態查詢介面（非即時性需求）

---

## 4. Application Cache（應用程式快取）

### 定位

| 項目 | 說明 |
|------|------|
| **所在位置** | 服務/應用程式層內部 |
| **快取內容** | 計算結果、用戶 Session、高頻查詢結果 |
| **核心價值** | 避免重複計算與重複查詢，降低延遲 |

### 關鍵元素

- **In-Memory Caching**：使用 `ConcurrentHashMap`、Caffeine、Guava Cache 等本地記憶體快取。
- **LRU / LFU Eviction**：快取滿時的淘汰策略 — Least Recently Used 或 Least Frequently Used。
- **Session Caching**：將用戶登入狀態、購物車等 Session 資料快取在記憶體中。
- **Feature Flags Caching**：快取功能開關設定，避免每次請求都查詢配置服務。
- **Precomputed Responses**：預先計算好的回應（如報表數據、統計摘要）。
- **Cache Warming**：應用啟動時預先載入熱點資料，避免冷啟動效能低落。
- **Stale Data Handling**：定義過期資料的處理策略（返回過期資料 + 背景更新，或直接穿透查詢）。
- **Low Latency Reads**：本地記憶體讀取通常在微秒等級。

### Spring Boot 實作範例

```java
@Service
public class ProductService {

    @Cacheable(value = "products", key = "#productId",
               unless = "#result == null")
    public Product getProduct(String productId) {
        // 只在快取未命中時才查詢資料庫
        return productRepository.findById(productId)
            .orElseThrow(() -> new ProductNotFoundException(productId));
    }

    @CacheEvict(value = "products", key = "#product.id")
    public Product updateProduct(Product product) {
        return productRepository.save(product);
    }
}
```

### 適用場景

- 銀行的客戶風險評等快取（計算成本高，結果穩定性高）
- 電商的商品價格快取（搭配 TTL 控制新鮮度）
- 保險業的費率表快取（日內不變，每日更新）

---

## 5. Database Cache（資料庫快取）

### 定位

| 項目 | 說明 |
|------|------|
| **所在位置** | 資料庫層或 DB 引擎內部 |
| **快取內容** | 查詢結果、高頻存取的資料列 |
| **核心價值** | 減少磁碟 I/O，加速重複讀取 |

### 關鍵元素

- **Query Caching**：相同的 SQL 查詢直接返回快取結果（注意：MySQL 8.0 已移除 Query Cache）。
- **Buffer Pool Caching**：InnoDB Buffer Pool 將熱點資料頁快取在記憶體中。
- **Index Caching**：索引頁面常駐記憶體，加速查詢計畫執行。
- **Hot Row Caching**：高頻存取的資料列保持在記憶體中。
- **Reduced DB I/O**：有效的快取策略可減少 80%+ 的磁碟讀取。
- **Cache Invalidation Complexity**：資料更新時的快取失效處理是最大挑戰。
- **Works Best with Reads**：讀多寫少的場景效益最大。

### 調優建議

```sql
-- 檢查 InnoDB Buffer Pool 命中率
SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read%';

-- 計算命中率
-- Hit Ratio = 1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests)
-- 目標 > 99%

-- 調整 Buffer Pool 大小（通常設為可用記憶體的 70-80%）
SET GLOBAL innodb_buffer_pool_size = 8589934592; -- 8GB
```

---

## 6. Distributed Cache（分散式快取）

### 定位

| 項目 | 說明 |
|------|------|
| **所在位置** | 獨立的共享快取叢集 |
| **快取內容** | 跨服務共享的資料 |
| **核心價值** | 微服務架構中的共享狀態管理 |

### 關鍵元素

- **Redis / Memcached**：最常見的分散式快取實作。
- **Horizontal Scaling**：透過增加節點水平擴展快取容量。
- **TTL-based Caching**：以存活時間控制快取生命週期。
- **Cache Replication**：主從複製確保讀取高可用。
- **Cluster Partitioning**：資料分片（Sharding）分散到多個節點。
- **High Availability Setup**：Redis Sentinel 或 Redis Cluster 提供故障自動轉移。
- **Cache Consistency Issues**：分散式環境下的一致性挑戰（Cache-Aside、Read-Through 等模式）。
- **Used in Microservices**：微服務架構的核心基礎設施之一。

### Redis 架構選型指南

| 模式 | 適用場景 | 特點 |
|------|---------|------|
| **Standalone** | 開發/測試環境 | 簡單，無高可用 |
| **Sentinel** | 中小規模生產環境 | 自動故障轉移，讀寫分離 |
| **Cluster** | 大規模生產環境 | 資料分片，水平擴展 |

### Spring Boot + Redis 範例

```java
@Configuration
@EnableCaching
public class RedisCacheConfig {

    @Bean
    public RedisCacheManager cacheManager(
            RedisConnectionFactory connectionFactory) {

        RedisCacheConfiguration config = RedisCacheConfiguration
            .defaultCacheConfig()
            .entryTtl(Duration.ofMinutes(10))
            .serializeValuesWith(
                SerializationPair.fromSerializer(
                    new GenericJackson2JsonRedisSerializer()));

        return RedisCacheManager.builder(connectionFactory)
            .cacheDefaults(config)
            .withCacheConfiguration("sessions",
                config.entryTtl(Duration.ofHours(1)))
            .withCacheConfiguration("products",
                config.entryTtl(Duration.ofMinutes(5)))
            .build();
    }
}
```

---

## 7. Write-Through Cache（寫穿快取）

### 定位

| 項目 | 說明 |
|------|------|
| **運作方式** | 同時寫入快取與資料庫 |
| **最適場景** | 強一致性需求的場景 |
| **核心價值** | 低過期資料風險，讀取始終快速 |

### 關鍵元素

- **Cache Always Updated**：快取與 DB 同步更新，永遠保持一致。
- **DB Write Guaranteed**：每次寫入都確保落盤。
- **Low Stale-Data Risk**：幾乎不會讀到過期資料。
- **Slower Writes**：寫入延遲較高（需等待 DB 確認）。
- **Read Becomes Fast**：讀取永遠命中快取。
- **Predictable Consistency**：一致性模型簡單可預測。
- **Easy Logic to Maintain**：實作邏輯直觀，易於維護。
- **Great for Critical Data**：適用於不容許資料不一致的關鍵業務。

### 適用場景

- **銀行帳戶餘額**：餘額必須即時正確，不能容忍過期數據。
- **庫存數量**：電商的即時庫存必須準確。
- **用戶權限設定**：安全相關資料變更必須立即生效。

### 流程示意

```
寫入請求
   │
   ├──► 寫入 Cache ──► 成功
   │
   └──► 寫入 DB ────► 成功
   │
   ▼
回應客戶端（兩者都成功才回應）
```

---

## 8. Write-Back Cache / Write-Behind（寫回快取）

### 定位

| 項目 | 說明 |
|------|------|
| **運作方式** | 先寫入快取，稍後非同步寫入資料庫 |
| **最適場景** | 高寫入量、對延遲敏感的系統 |
| **核心價值** | 極快的寫入速度 |

### 關鍵元素

- **Super Fast Writes**：寫入只需等待快取回應，極低延遲。
- **Async DB Sync**：背景程序批次或定時將資料同步到 DB。
- **Risk of Data Loss**：快取節點崩潰時，未同步的資料可能遺失。
- **Needs Durability Queue**：通常搭配持久化佇列（如 Redis AOF、Kafka）降低遺失風險。
- **Flush Scheduling Logic**：控制何時將髒資料寫回 DB 的排程邏輯。
- **Crash Recovery Planning**：必須有完善的故障恢復計畫。
- **Best for Non-Critical Writes**：最適合可容忍少量資料遺失的場景。
- **Requires Careful Monitoring**：需要密切監控同步佇列深度與延遲。

### 適用場景

- **頁面瀏覽計數器**：高頻寫入，少量遺失可接受。
- **IoT 感測器數據**：大量寫入，允許批次處理。
- **用戶行為日誌**：點擊流、瀏覽記錄等分析數據。

### 流程示意

```
寫入請求
   │
   ▼
寫入 Cache ──► 立即回應客戶端
   │
   ▼（非同步）
排程/批次寫入 DB
   │
   ▼
確認持久化 ──► 標記快取項目為已同步
```

---

## 快取策略決策矩陣

| 維度 | Write-Through | Write-Back | Cache-Aside |
|------|:---:|:---:|:---:|
| **寫入延遲** | 高 | 低 | 中 |
| **讀取延遲** | 低 | 低 | 首次高，後續低 |
| **資料一致性** | 強 | 最終一致 | 最終一致 |
| **資料遺失風險** | 極低 | 中～高 | 低 |
| **實作複雜度** | 低 | 高 | 中 |
| **適用場景** | 金融交易 | 日誌/計數器 | 通用查詢 |

---

## 企業架構中的快取設計原則

### 1. 分層思考（Think in Layers）

不要只在單一層級加快取。從瀏覽器到資料庫，每一層都有適合的快取策略。關鍵是確定每一層快取的**職責邊界**。

### 2. 失效策略優先（Invalidation First）

設計快取時先想清楚「怎麼讓它過期」，而不是「怎麼把資料放進去」。Cache invalidation 是電腦科學中公認的兩大難題之一。

### 3. 監控與可觀測性（Observability）

每一層快取都應該有監控指標：命中率（Hit Ratio）、延遲（Latency）、記憶體使用量（Memory Usage）、淘汰次數（Eviction Count）。

### 4. 優雅降級（Graceful Degradation）

快取層失效時，系統應該能夠降級到下一層，而不是直接崩潰。設計 Circuit Breaker 和 Fallback 機制。

### 5. 安全性考量（Security）

快取中可能包含敏感資料（Session Token、個資）。確保快取的存取控制、加密傳輸、以及適當的 TTL 設定。

---

## 總結

快取不是「加個 Redis 就好」的事情。它是一個**多層次的架構決策**，涉及到從前端到資料庫的每一個環節。理解這 8 種快取類型及其適用場景，能幫助你在系統設計中做出更精確的架構決策，打造出真正高效能、高可用的企業級系統。

---

*基於 Rocky Bhatia 的「8 Types of Caching Used in System Design」整理與擴充*
