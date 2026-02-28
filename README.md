# 系統設計中的 8 種快取類型 — 實作教學與驗證

> 快取不等於 Redis。在真實系統中，快取是一個**多層堆疊（Caching Stack）**，從瀏覽器到資料庫，每一層解決不同問題、以不同方式失效。

本教學將帶你逐一認識 8 種快取類型，並透過**可在本機執行的實驗**來驗證每種快取的行為。

---

## 目錄

1. [前置準備](#前置準備)
2. [快取層級總覽](#快取層級總覽)
3. [Lab 1：Browser Cache（瀏覽器快取）](#lab-1browser-cache瀏覽器快取)
4. [Lab 2：CDN Cache（內容傳遞網路快取）](#lab-2cdn-cache內容傳遞網路快取)
5. [Lab 3：Reverse Proxy Cache（反向代理快取）](#lab-3reverse-proxy-cache反向代理快取)
6. [Lab 4：Application Cache（應用程式快取）](#lab-4application-cache應用程式快取)
7. [Lab 5：Database Cache（資料庫快取）](#lab-5database-cache資料庫快取)
8. [Lab 6：Distributed Cache（分散式快取）](#lab-6distributed-cache分散式快取)
9. [Lab 7：Write-Through Cache（寫穿快取）](#lab-7write-through-cache寫穿快取)
10. [Lab 8：Write-Back Cache（寫回快取）](#lab-8write-back-cache寫回快取)
11. [快取策略決策矩陣](#快取策略決策矩陣)
12. [企業架構中的快取設計原則](#企業架構中的快取設計原則)

---

## 前置準備

請確認以下工具已安裝：

```bash
# 檢查 Docker（用於 NGINX、Redis、MySQL 實驗）
docker --version

# 檢查 curl（用於 HTTP 請求驗證）
curl --version

# 檢查 Redis CLI（可選，也可透過 Docker 執行）
redis-cli --version 2>/dev/null || echo "將透過 Docker 使用 redis-cli"

# 檢查 Python 3（用於簡易 HTTP Server）
python3 --version

# 檢查 Node.js（可選，用於 Application Cache 範例）
node --version 2>/dev/null || echo "Node.js 未安裝，Application Cache Lab 將使用 Python 替代"
```

---

## 快取層級總覽

一個請求從用戶端到資料庫，可能經過以下 4～5 層快取：

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

每一層都有其設計取捨（trade-off）：

| 取捨維度 | 說明 |
|---------|------|
| **延遲 vs. 一致性** | 越靠近用戶端，延遲越低，但資料新鮮度越難保證 |
| **命中率 vs. 記憶體成本** | 快取越多資料，命中率越高，但記憶體與管理成本也越高 |
| **寫入速度 vs. 資料持久性** | Write-Back 寫入飛快，但節點崩潰時未落盤的資料可能遺失 |

> 寫入策略（Write-Through / Write-Back）橫跨多個層級，決定資料如何從快取同步到持久化儲存。

---

## Lab 1：Browser Cache（瀏覽器快取）

### 概念

| 項目 | 說明 |
|------|------|
| **所在位置** | 用戶的瀏覽器 |
| **快取內容** | 靜態前端資源（HTML、CSS、JS、圖片、字型） |
| **核心價值** | 重複造訪時幾乎零延遲 |

**關鍵元素：**
- **Cache-Control Headers**：透過 `max-age`、`no-cache`、`no-store` 控制快取行為
- **ETag / If-None-Match**：條件式請求，伺服器回傳 304 Not Modified 時不重傳內容
- **Service Worker Cache**：PWA 離線快取策略
- **Stale Assets Risk**：版本更新後需搭配 cache-busting（如檔名加 hash）

### 實作步驟

**步驟 1：建立測試目錄與靜態檔案**

```bash
mkdir -p lab1-browser-cache
cd lab1-browser-cache

# 建立靜態 HTML 檔案
cat > index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Browser Cache Lab</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <h1>Browser Cache 測試頁面</h1>
    <p>檢查 Network tab 觀察快取行為</p>
    <img src="logo.svg" alt="logo">
    <script src="app.js"></script>
</body>
</html>
EOF

cat > style.css << 'EOF'
body { font-family: sans-serif; max-width: 800px; margin: 50px auto; }
h1 { color: #2563eb; }
EOF

cat > app.js << 'EOF'
console.log('App loaded at:', new Date().toISOString());
EOF

# 建立一個簡單的 SVG 圖片
cat > logo.svg << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
  <circle cx="50" cy="50" r="40" fill="#2563eb"/>
  <text x="50" y="55" text-anchor="middle" fill="white" font-size="16">Cache</text>
</svg>
EOF
```

**步驟 2：使用 Python 啟動帶有快取 Header 的 HTTP Server**

```bash
cat > cache_server.py << 'PYEOF'
from http.server import HTTPServer, SimpleHTTPRequestHandler
import hashlib
import os
import time

class CacheHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        path = self.translate_path(self.path)
        if os.path.isfile(path):
            # 為不同類型的資源設定不同的快取策略
            if self.path.endswith(('.js', '.css', '.svg')):
                # 靜態資源：快取 1 小時
                self.send_header('Cache-Control', 'public, max-age=3600')
            elif self.path.endswith('.html') or self.path == '/':
                # HTML：每次都重新驗證
                self.send_header('Cache-Control', 'no-cache')

            # 加入 ETag
            stat = os.stat(path)
            etag = hashlib.md5(f"{stat.st_mtime}-{stat.st_size}".encode()).hexdigest()
            self.send_header('ETag', f'"{etag}"')

        super().end_headers()

    def do_GET(self):
        # 處理條件式請求（If-None-Match）
        path = self.translate_path(self.path)
        if os.path.isfile(path):
            stat = os.stat(path)
            etag = hashlib.md5(f"{stat.st_mtime}-{stat.st_size}".encode()).hexdigest()
            if self.headers.get('If-None-Match') == f'"{etag}"':
                self.send_response(304)
                self.end_headers()
                return

        super().do_GET()

print("Server running at http://localhost:8080")
print("Open browser DevTools > Network tab to observe caching behavior")
HTTPServer(('', 8080), CacheHandler).serve_forever()
PYEOF

python3 cache_server.py
```

### 驗證方法

1. 開啟瀏覽器，前往 `http://localhost:8080`
2. 開啟 DevTools（F12）> Network tab
3. 重新整理頁面（F5），觀察：

```
驗證點 1：首次請求
  - 所有資源顯示 Status 200
  - Response Headers 包含 Cache-Control 和 ETag

驗證點 2：第二次重新整理（Soft Refresh）
  - CSS/JS/SVG 顯示 "(from disk cache)" 或 "(from memory cache)"
  - 或顯示 Status 304 Not Modified
  - HTML 仍送出請求（因為設定 no-cache）但可能收到 304

驗證點 3：Hard Refresh（Ctrl+Shift+R）
  - 所有資源重新下載，Status 200
  - Request Headers 包含 Cache-Control: no-cache
```

用 curl 驗證 Header：

```bash
# 觀察回應 Header
curl -I http://localhost:8080/style.css

# 驗證 ETag 條件式請求（用上一步拿到的 ETag 值替換）
curl -I -H 'If-None-Match: "<your-etag>"' http://localhost:8080/style.css
# 應收到 304 Not Modified
```

完成後按 `Ctrl+C` 停止 server，回到上層目錄：

```bash
cd ..
```

### 典型的 Cache-Control 設定

```
# 靜態資源（帶 hash 的 JS/CSS）— 快取一年，不可變
Cache-Control: public, max-age=31536000, immutable

# HTML 入口頁面 — 每次都重新驗證
Cache-Control: no-cache

# API 回應 — 私有、不快取
Cache-Control: private, max-age=0, must-revalidate
```

### 適用場景

- 銀行網銀前端的靜態資源（logo、CSS framework）
- 電商網站的商品圖片縮圖
- 企業內部系統的 SPA 應用靜態檔案

---

## Lab 2：CDN Cache（內容傳遞網路快取）

### 概念

| 項目 | 說明 |
|------|------|
| **所在位置** | 全球邊緣節點（Edge Locations） |
| **快取內容** | 圖片、JS/CSS、影片、靜態頁面 |
| **核心價值** | 地理位置就近回應，降低延遲並保護源站 |

**關鍵元素：**
- **Edge Caching**：將內容複製到靠近用戶的邊緣節點
- **Geo-based Delivery**：根據地理位置路由到最近的 PoP
- **TTL Settings**：控制邊緣節點快取的存活時間
- **Origin Shielding**：在 CDN 與源站之間加一層 Shield 節點，減少回源請求
- **Cache Invalidation**：內容更新時主動清除 CDN 快取
- **Cache Hit Ratio**：目標通常 > 90%

### 實作步驟（使用 Cloudflare 模擬）

> 由於 CDN 需要實際的邊緣節點，我們使用 curl 觀察真實 CDN 的快取行為。

**方法 A：觀察真實網站的 CDN 行為**

```bash
# 觀察 CDN 快取 Header（以 jQuery CDN 為例）
curl -sI https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js | grep -iE '(cache-control|cf-cache-status|age|x-cache|cdn)'
```

**方法 B：用 Docker 模擬 CDN 邊緣快取概念**

```bash
mkdir -p lab2-cdn-cache
cd lab2-cdn-cache

# 建立源站內容
mkdir -p origin
echo '{"rate": "31.2", "timestamp": "'$(date -Iseconds)'"}' > origin/exchange-rate.json
echo '<html><body><h1>CDN Origin Content</h1></body></html>' > origin/index.html

# 建立 NGINX 配置模擬 CDN 邊緣快取
cat > nginx-cdn.conf << 'EOF'
proxy_cache_path /var/cache/nginx/cdn levels=1:2
    keys_zone=cdn_cache:10m max_size=100m inactive=60m;

server {
    listen 80;

    # 模擬 CDN 邊緣節點快取
    location / {
        proxy_cache cdn_cache;
        proxy_cache_valid 200 30s;
        proxy_cache_use_stale error timeout updating;

        # 加入 CDN 特徵 Header
        add_header X-Cache-Status $upstream_cache_status always;
        add_header X-Edge-Location "TW-TPE" always;
        add_header Age $upstream_cache_status always;

        proxy_pass http://origin:8000;
    }

    # 模擬 Cache Purge 端點
    location /purge {
        # 在真實 CDN 中，這會清除邊緣節點快取
        return 200 '{"status": "purged", "message": "Cache cleared"}\n';
        add_header Content-Type application/json;
    }
}
EOF

# 建立源站 Python Server
cat > origin_server.py << 'PYEOF'
from http.server import HTTPServer, SimpleHTTPRequestHandler
import json, time, os

class OriginHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory="origin", **kwargs)

    def do_GET(self):
        # 模擬源站處理延遲
        time.sleep(0.5)
        print(f"[ORIGIN HIT] {self.path} at {time.strftime('%H:%M:%S')}")
        if self.path == '/exchange-rate.json':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'public, max-age=30')
            self.end_headers()
            data = {"rate": "31.2", "timestamp": time.strftime('%H:%M:%S'), "source": "origin"}
            self.wfile.write(json.dumps(data).encode())
        else:
            super().do_GET()

HTTPServer(('', 8000), OriginHandler).serve_forever()
PYEOF

# 建立 docker-compose.yml
cat > docker-compose.yml << 'EOF'
services:
  origin:
    image: python:3.11-slim
    working_dir: /app
    volumes:
      - ./origin_server.py:/app/origin_server.py
      - ./origin:/app/origin
    command: python origin_server.py

  cdn-edge:
    image: nginx:alpine
    ports:
      - "8081:80"
    volumes:
      - ./nginx-cdn.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - origin
EOF

docker compose up -d
```

### 驗證方法

```bash
# 等待服務啟動
sleep 3

# 驗證點 1：首次請求（MISS — 需回源）
echo "=== 第 1 次請求（應為 MISS）==="
curl -s -o /dev/null -w "HTTP Status: %{http_code}, Time: %{time_total}s\n" \
  -D - http://localhost:8081/exchange-rate.json 2>&1 | grep -iE '(HTTP|X-Cache|X-Edge|Time:)'

# 驗證點 2：第二次請求（HIT — 從邊緣快取回應）
echo -e "\n=== 第 2 次請求（應為 HIT）==="
curl -s -o /dev/null -w "HTTP Status: %{http_code}, Time: %{time_total}s\n" \
  -D - http://localhost:8081/exchange-rate.json 2>&1 | grep -iE '(HTTP|X-Cache|X-Edge|Time:)'

# 驗證點 3：觀察源站日誌（應只有 1 次回源）
echo -e "\n=== 源站日誌 ==="
docker compose logs origin 2>&1 | grep "ORIGIN HIT"

# 驗證點 4：等待 TTL 過期後再次請求
echo -e "\n等待 35 秒讓快取過期..."
sleep 35
echo "=== TTL 過期後的請求（應為 MISS 或 EXPIRED）==="
curl -s -D - http://localhost:8081/exchange-rate.json 2>&1 | grep -iE '(X-Cache|timestamp)'
```

預期輸出：

```
=== 第 1 次請求（應為 MISS）===
X-Cache-Status: MISS          <-- 快取未命中，回源取得
Time: 0.5xxs                  <-- 包含源站 0.5s 延遲

=== 第 2 次請求（應為 HIT）===
X-Cache-Status: HIT           <-- 快取命中！
Time: 0.00xs                  <-- 幾乎零延遲
```

清理：

```bash
docker compose down
cd ..
```

### 適用場景

- 金融業的公開資訊頁面（匯率公告），TTL 設短（60 秒）
- 電商的商品圖片，TTL 設長（24 小時），搭配版本化 URL
- 促銷活動期間使用 Origin Shielding 降低源站負載

---

## Lab 3：Reverse Proxy Cache（反向代理快取）

### 概念

| 項目 | 說明 |
|------|------|
| **所在位置** | 客戶端與後端服務之間 |
| **快取內容** | API 回應、HTML 頁面 |
| **核心價值** | 減輕後端負載、加速 API 交付 |

**關鍵元素：**
- **NGINX / Varnish Caching**：最常見的反向代理快取實作
- **Cache Key Design**：精心設計快取鍵，避免快取汙染
- **Rate Limiting Support**：在代理層實作限流
- **Load Reduction**：可減少 70%+ 的後端請求

### 實作步驟

```bash
mkdir -p lab3-reverse-proxy
cd lab3-reverse-proxy

# 建立後端 API Server
cat > backend.py << 'PYEOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
import json, time, random

request_count = 0

class BackendHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global request_count
        request_count += 1
        time.sleep(0.3)  # 模擬 DB 查詢延遲

        if self.path == '/api/v1/products':
            data = {
                "products": [
                    {"id": 1, "name": "Laptop", "price": 35000},
                    {"id": 2, "name": "Phone", "price": 15000},
                ],
                "generated_at": time.strftime('%H:%M:%S'),
                "backend_request_count": request_count
            }
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(data, indent=2).encode())
        elif self.path == '/api/v1/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "requests_served": request_count}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        print(f"[BACKEND #{request_count}] {args[0]}")

HTTPServer(('', 8000), BackendHandler).serve_forever()
PYEOF

# 建立 NGINX 反向代理快取配置
cat > nginx.conf << 'EOF'
proxy_cache_path /var/cache/nginx levels=1:2
    keys_zone=api_cache:10m max_size=1g inactive=60m;

server {
    listen 80;

    # 快取 API 回應
    location /api/v1/products {
        proxy_cache api_cache;
        proxy_cache_valid 200 10s;
        proxy_cache_valid 404 5s;
        proxy_cache_key "$scheme$request_method$host$request_uri";

        # 加入快取狀態 Header
        add_header X-Cache-Status $upstream_cache_status always;
        add_header X-Cache-Key "$scheme$request_method$host$request_uri" always;

        proxy_pass http://backend:8000;
    }

    # 不快取健康檢查
    location /api/v1/health {
        proxy_pass http://backend:8000;
        add_header X-Cache-Status "BYPASS" always;
    }
}
EOF

# 建立 docker-compose.yml
cat > docker-compose.yml << 'EOF'
services:
  backend:
    image: python:3.11-slim
    working_dir: /app
    volumes:
      - ./backend.py:/app/backend.py
    command: python backend.py

  proxy:
    image: nginx:alpine
    ports:
      - "8082:80"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - backend
EOF

docker compose up -d
sleep 3
```

### 驗證方法

```bash
# 驗證點 1：觀察快取 MISS → HIT 轉換
echo "=== 第 1 次請求（MISS）==="
curl -s -D - http://localhost:8082/api/v1/products | grep -iE '(X-Cache|generated_at|backend_request)'

echo -e "\n=== 第 2 次請求（HIT）==="
curl -s -D - http://localhost:8082/api/v1/products | grep -iE '(X-Cache|generated_at|backend_request)'

echo -e "\n=== 第 3 次請求（HIT）==="
curl -s -D - http://localhost:8082/api/v1/products | grep -iE '(X-Cache|generated_at|backend_request)'

# 驗證點 2：確認後端只收到 1 次請求
echo -e "\n=== 後端實際請求數 ==="
curl -s http://localhost:8082/api/v1/health | python3 -m json.tool

# 驗證點 3：壓力測試 — 100 個請求，後端應只處理極少數
echo -e "\n=== 壓力測試：送出 100 個請求 ==="
for i in $(seq 1 100); do
    curl -s -o /dev/null http://localhost:8082/api/v1/products
done
echo "後端實際處理的請求數："
curl -s http://localhost:8082/api/v1/health | python3 -m json.tool

# 驗證點 4：等待快取過期
echo -e "\n等待 12 秒讓快取過期..."
sleep 12
echo "=== 快取過期後的請求（EXPIRED → MISS）==="
curl -s -D - http://localhost:8082/api/v1/products | grep -iE '(X-Cache|generated_at)'
```

預期輸出：

```
=== 第 1 次請求（MISS）===
X-Cache-Status: MISS
"generated_at": "14:30:01"
"backend_request_count": 1

=== 第 2 次請求（HIT）===
X-Cache-Status: HIT
"generated_at": "14:30:01"         <-- 時間不變！來自快取
"backend_request_count": 1         <-- 後端沒有收到新請求

=== 壓力測試：送出 100 個請求 ===
後端實際處理的請求數：
{
    "requests_served": 2~3         <-- 100 個請求只穿透了 2~3 個！
}
```

清理：

```bash
docker compose down
cd ..
```

### NGINX 快取配置參考

```nginx
proxy_cache_path /var/cache/nginx levels=1:2
    keys_zone=api_cache:10m max_size=1g inactive=60m;

location /api/v1/products {
    proxy_cache api_cache;
    proxy_cache_valid 200 5m;       # 200 回應快取 5 分鐘
    proxy_cache_valid 404 1m;       # 404 回應快取 1 分鐘
    proxy_cache_key "$scheme$request_method$host$request_uri";
    proxy_pass http://backend;
}
```

---

## Lab 4：Application Cache（應用程式快取）

### 概念

| 項目 | 說明 |
|------|------|
| **所在位置** | 服務/應用程式層內部 |
| **快取內容** | 計算結果、用戶 Session、高頻查詢結果 |
| **核心價值** | 避免重複計算與重複查詢，降低延遲 |

**關鍵元素：**
- **In-Memory Caching**：本地記憶體快取（微秒等級讀取）
- **LRU / LFU Eviction**：快取滿時的淘汰策略
- **Cache Warming**：啟動時預先載入熱點資料
- **Stale Data Handling**：過期資料處理策略

### 實作步驟（Python + 本地快取）

```bash
mkdir -p lab4-app-cache
cd lab4-app-cache

cat > app_cache_demo.py << 'PYEOF'
import time
import functools
from collections import OrderedDict
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

# ========== 自製 LRU Cache ==========
class LRUCache:
    def __init__(self, capacity=100, ttl_seconds=10):
        self.capacity = capacity
        self.ttl = ttl_seconds
        self.cache = OrderedDict()
        self.stats = {"hits": 0, "misses": 0}

    def get(self, key):
        if key in self.cache:
            value, timestamp = self.cache[key]
            if time.time() - timestamp < self.ttl:
                self.cache.move_to_end(key)
                self.stats["hits"] += 1
                return value
            else:
                del self.cache[key]
        self.stats["misses"] += 1
        return None

    def put(self, key, value):
        if key in self.cache:
            del self.cache[key]
        elif len(self.cache) >= self.capacity:
            self.cache.popitem(last=False)  # 移除最久未使用的
        self.cache[key] = (value, time.time())

    def hit_ratio(self):
        total = self.stats["hits"] + self.stats["misses"]
        return self.stats["hits"] / total if total > 0 else 0

# ========== 模擬昂貴的計算 ==========
def expensive_computation(product_id):
    """模擬需要 500ms 的資料庫查詢"""
    time.sleep(0.5)
    return {
        "id": product_id,
        "name": f"Product-{product_id}",
        "price": product_id * 100,
        "computed_at": time.strftime('%H:%M:%S')
    }

# ========== 初始化快取 ==========
cache = LRUCache(capacity=50, ttl_seconds=15)

# ========== HTTP Server ==========
class AppHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/api/product/'):
            product_id = self.path.split('/')[-1]
            start = time.time()

            # 嘗試從快取讀取
            result = cache.get(f"product:{product_id}")
            cache_hit = result is not None

            if not cache_hit:
                result = expensive_computation(int(product_id))
                cache.put(f"product:{product_id}", result)

            elapsed = time.time() - start
            response = {
                **result,
                "cache_hit": cache_hit,
                "response_time_ms": round(elapsed * 1000, 2),
                "cache_hit_ratio": f"{cache.hit_ratio():.1%}"
            }

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response, indent=2).encode())

        elif self.path == '/api/cache/stats':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                "hits": cache.stats["hits"],
                "misses": cache.stats["misses"],
                "hit_ratio": f"{cache.hit_ratio():.1%}",
                "cached_items": len(cache.cache),
                "capacity": cache.capacity,
                "ttl_seconds": cache.ttl
            }, indent=2).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # 靜默日誌

print("Application Cache Server running at http://localhost:8083")
print("TTL=15s, Capacity=50 items, LRU eviction")
HTTPServer(('', 8083), AppHandler).serve_forever()
PYEOF

python3 app_cache_demo.py &
APP_PID=$!
sleep 1
```

### 驗證方法

```bash
# 驗證點 1：首次請求（MISS — 500ms 延遲）
echo "=== 首次請求 Product 1（Cache MISS）==="
curl -s http://localhost:8083/api/product/1 | python3 -m json.tool

# 驗證點 2：第二次請求（HIT — 接近 0ms）
echo -e "\n=== 再次請求 Product 1（Cache HIT）==="
curl -s http://localhost:8083/api/product/1 | python3 -m json.tool

# 驗證點 3：批量請求，觀察命中率
echo -e "\n=== 批量請求：10 次 Product 1~3 ==="
for i in 1 2 3 1 2 3 1 2 3 1; do
    curl -s http://localhost:8083/api/product/$i > /dev/null
done
echo "快取統計："
curl -s http://localhost:8083/api/cache/stats | python3 -m json.tool

# 驗證點 4：等待 TTL 過期
echo -e "\n等待 16 秒讓快取過期..."
sleep 16
echo "=== 過期後請求（Cache MISS，時間戳改變）==="
curl -s http://localhost:8083/api/product/1 | python3 -m json.tool

# 清理
kill $APP_PID 2>/dev/null
cd ..
```

預期輸出：

```
=== 首次請求 Product 1（Cache MISS）===
{
  "id": 1,
  "name": "Product-1",
  "price": 100,
  "computed_at": "14:30:01",
  "cache_hit": false,
  "response_time_ms": 502.3,      <-- 慢！經過資料庫查詢
  "cache_hit_ratio": "0.0%"
}

=== 再次請求 Product 1（Cache HIT）===
{
  "id": 1,
  "name": "Product-1",
  "price": 100,
  "computed_at": "14:30:01",       <-- 時間不變！來自快取
  "cache_hit": true,
  "response_time_ms": 0.12,        <-- 快 4000 倍！
  "cache_hit_ratio": "50.0%"
}
```

### Spring Boot 實作參考

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

---

## Lab 5：Database Cache（資料庫快取）

### 概念

| 項目 | 說明 |
|------|------|
| **所在位置** | 資料庫層或 DB 引擎內部 |
| **快取內容** | 查詢結果、高頻存取的資料列 |
| **核心價值** | 減少磁碟 I/O，加速重複讀取 |

**關鍵元素：**
- **Buffer Pool Caching**：InnoDB Buffer Pool 將熱點資料頁快取在記憶體中
- **Index Caching**：索引頁面常駐記憶體
- **Hot Row Caching**：高頻存取的資料列保持在記憶體中
- **Reduced DB I/O**：有效策略可減少 80%+ 磁碟讀取
- 注意：MySQL 8.0 已移除 Query Cache

### 實作步驟

```bash
mkdir -p lab5-db-cache
cd lab5-db-cache

cat > docker-compose.yml << 'EOF'
services:
  mysql:
    image: mysql:8.0
    ports:
      - "3306:3306"
    environment:
      MYSQL_ROOT_PASSWORD: rootpass
      MYSQL_DATABASE: cache_lab
    command: >
      --innodb-buffer-pool-size=128M
      --innodb-buffer-pool-instances=1
    volumes:
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
EOF

cat > init.sql << 'EOF'
USE cache_lab;

CREATE TABLE products (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100),
    price DECIMAL(10,2),
    category VARCHAR(50),
    INDEX idx_category (category)
) ENGINE=InnoDB;

-- 插入 10000 筆測試資料
DELIMITER //
CREATE PROCEDURE generate_data()
BEGIN
    DECLARE i INT DEFAULT 1;
    WHILE i <= 10000 DO
        INSERT INTO products (name, price, category)
        VALUES (
            CONCAT('Product-', i),
            ROUND(RAND() * 10000, 2),
            ELT(1 + FLOOR(RAND() * 5), 'Electronics', 'Clothing', 'Food', 'Books', 'Sports')
        );
        SET i = i + 1;
    END WHILE;
END //
DELIMITER ;

CALL generate_data();
EOF

docker compose up -d
echo "等待 MySQL 啟動..."
sleep 15
```

### 驗證方法

```bash
# 驗證點 1：檢查 Buffer Pool 狀態
echo "=== InnoDB Buffer Pool 狀態 ==="
docker exec lab5-db-cache-mysql-1 mysql -uroot -prootpass -e "
SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool%';
" 2>/dev/null | grep -E '(read_requests|reads|pool_size|pages_data)'

# 驗證點 2：首次查詢（可能需要磁碟 I/O）
echo -e "\n=== 執行查詢前的 I/O 狀態 ==="
docker exec lab5-db-cache-mysql-1 mysql -uroot -prootpass -e "
SHOW GLOBAL STATUS WHERE Variable_name IN ('Innodb_buffer_pool_read_requests', 'Innodb_buffer_pool_reads');
" 2>/dev/null

echo -e "\n=== 執行查詢 ==="
docker exec lab5-db-cache-mysql-1 mysql -uroot -prootpass cache_lab -e "
SELECT category, COUNT(*) as cnt, AVG(price) as avg_price
FROM products
GROUP BY category;
" 2>/dev/null

# 驗證點 3：重複相同查詢，觀察 I/O 變化
echo -e "\n=== 重複執行 5 次相同查詢 ==="
for i in $(seq 1 5); do
    docker exec lab5-db-cache-mysql-1 mysql -uroot -prootpass cache_lab -e "
    SELECT * FROM products WHERE category = 'Electronics' LIMIT 10;
    " 2>/dev/null > /dev/null
done

echo "=== 查詢後的 I/O 狀態 ==="
docker exec lab5-db-cache-mysql-1 mysql -uroot -prootpass -e "
SHOW GLOBAL STATUS WHERE Variable_name IN ('Innodb_buffer_pool_read_requests', 'Innodb_buffer_pool_reads');
" 2>/dev/null

# 驗證點 4：計算命中率
echo -e "\n=== Buffer Pool 命中率計算 ==="
docker exec lab5-db-cache-mysql-1 mysql -uroot -prootpass -e "
SELECT
  (1 - (
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads')
    /
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
  )) * 100 AS buffer_pool_hit_ratio_pct;
" 2>/dev/null
```

預期輸出：

```
=== Buffer Pool 命中率計算 ===
+----------------------------+
| buffer_pool_hit_ratio_pct  |
+----------------------------+
|                    99.8500 |   <-- 目標 > 99%
+----------------------------+
```

清理：

```bash
docker compose down -v
cd ..
```

### 調優建議

```sql
-- 檢查 InnoDB Buffer Pool 命中率
SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read%';

-- 命中率公式：
-- Hit Ratio = 1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests)
-- 目標 > 99%

-- 調整 Buffer Pool 大小（通常設為可用記憶體的 70-80%）
SET GLOBAL innodb_buffer_pool_size = 8589934592; -- 8GB
```

---

## Lab 6：Distributed Cache（分散式快取）

### 概念

| 項目 | 說明 |
|------|------|
| **所在位置** | 獨立的共享快取叢集 |
| **快取內容** | 跨服務共享的資料 |
| **核心價值** | 微服務架構中的共享狀態管理 |

**關鍵元素：**
- **Redis / Memcached**：最常見的分散式快取實作
- **TTL-based Caching**：以存活時間控制快取生命週期
- **Cache Replication**：主從複製確保讀取高可用
- **Cluster Partitioning**：資料分片分散到多個節點

### Redis 架構選型指南

| 模式 | 適用場景 | 特點 |
|------|---------|------|
| **Standalone** | 開發/測試環境 | 簡單，無高可用 |
| **Sentinel** | 中小規模生產環境 | 自動故障轉移，讀寫分離 |
| **Cluster** | 大規模生產環境 | 資料分片，水平擴展 |

### 實作步驟

```bash
mkdir -p lab6-distributed-cache
cd lab6-distributed-cache

# 啟動 Redis
cat > docker-compose.yml << 'EOF'
services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    command: redis-server --maxmemory 50mb --maxmemory-policy allkeys-lru
EOF

docker compose up -d
sleep 2

# 驗證 Redis 連線
docker exec lab6-distributed-cache-redis-1 redis-cli ping
```

### 驗證方法

```bash
REDIS_CLI="docker exec lab6-distributed-cache-redis-1 redis-cli"

# ========== 基本 CRUD 操作 ==========
echo "=== 1. 基本 Key-Value 操作 ==="
$REDIS_CLI SET "product:1001" '{"name":"Laptop","price":35000}' EX 60
$REDIS_CLI GET "product:1001"
$REDIS_CLI TTL "product:1001"

# ========== Session 快取 ==========
echo -e "\n=== 2. Session 快取 ==="
$REDIS_CLI HSET "session:abc123" "user_id" "42" "username" "rex" "role" "admin"
$REDIS_CLI EXPIRE "session:abc123" 3600
$REDIS_CLI HGETALL "session:abc123"

# ========== 批量操作 ==========
echo -e "\n=== 3. 批量寫入 1000 個 Key ==="
for i in $(seq 1 1000); do
    $REDIS_CLI SET "item:$i" "value-$i" EX 300 > /dev/null
done
echo "寫入完成"
$REDIS_CLI DBSIZE

# ========== 效能統計 ==========
echo -e "\n=== 4. 快取統計 ==="
$REDIS_CLI INFO stats | grep -E '(keyspace_hits|keyspace_misses|total_commands)'

# ========== 計算命中率 ==========
echo -e "\n=== 5. 讀取測試 ==="
# 讀取存在的 key
for i in $(seq 1 100); do
    $REDIS_CLI GET "item:$((RANDOM % 1000 + 1))" > /dev/null
done
# 讀取不存在的 key
for i in $(seq 1 20); do
    $REDIS_CLI GET "nonexist:$i" > /dev/null
done

echo "快取命中統計："
$REDIS_CLI INFO stats | grep -E '(keyspace_hits|keyspace_misses)'

# ========== 記憶體使用 ==========
echo -e "\n=== 6. 記憶體使用狀況 ==="
$REDIS_CLI INFO memory | grep -E '(used_memory_human|maxmemory_human|maxmemory_policy)'

# ========== TTL 過期驗證 ==========
echo -e "\n=== 7. TTL 過期驗證 ==="
$REDIS_CLI SET "temp:key" "expires-in-3s" EX 3
echo "寫入 temp:key（TTL=3s）"
echo "立即讀取: $($REDIS_CLI GET 'temp:key')"
sleep 4
echo "4 秒後讀取: $($REDIS_CLI GET 'temp:key')"
echo "(nil) 表示已過期被自動清除"
```

預期輸出：

```
=== 1. 基本 Key-Value 操作 ===
OK
{"name":"Laptop","price":35000}
(integer) 59

=== 5. 讀取測試 ===
快取命中統計：
keyspace_hits:1105            <-- 命中次數
keyspace_misses:20            <-- 未命中次數
                               <-- 命中率 = 1105/(1105+20) ≈ 98.2%

=== 7. TTL 過期驗證 ===
立即讀取: expires-in-3s
4 秒後讀取:                   <-- 空！已自動過期
```

清理：

```bash
docker compose down
cd ..
```

### Spring Boot + Redis 配置參考

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

## Lab 7：Write-Through Cache（寫穿快取）

### 概念

| 項目 | 說明 |
|------|------|
| **運作方式** | 同時寫入快取與資料庫 |
| **最適場景** | 強一致性需求 |
| **核心價值** | 低過期資料風險，讀取始終快速 |

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

**關鍵特性：** 快取與 DB 同步更新、寫入延遲較高（需等 DB 確認）、一致性模型簡單可預測。

### 實作步驟

```bash
mkdir -p lab7-write-through
cd lab7-write-through

cat > write_through.py << 'PYEOF'
import json, time, sqlite3
from http.server import HTTPServer, BaseHTTPRequestHandler

# ========== 初始化 ==========
cache = {}  # In-memory cache
db = sqlite3.connect("data.db", check_same_thread=False)
db.execute("CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY, name TEXT, balance REAL, updated_at TEXT)")
db.commit()

stats = {"cache_hits": 0, "cache_misses": 0, "writes": 0}

# ========== Write-Through 實作 ==========
def write_through(account_id, name, balance):
    """同時寫入快取與資料庫，兩者都成功才返回"""
    timestamp = time.strftime('%H:%M:%S')
    data = {"id": account_id, "name": name, "balance": balance, "updated_at": timestamp}

    # Step 1: 寫入資料庫
    db.execute(
        "INSERT OR REPLACE INTO accounts (id, name, balance, updated_at) VALUES (?, ?, ?, ?)",
        (account_id, name, balance, timestamp)
    )
    db.commit()

    # Step 2: 寫入快取
    cache[account_id] = data

    stats["writes"] += 1
    return data

def read_with_cache(account_id):
    """讀取：先查快取，未命中才查 DB"""
    if account_id in cache:
        stats["cache_hits"] += 1
        return {**cache[account_id], "source": "cache"}

    stats["cache_misses"] += 1
    row = db.execute("SELECT id, name, balance, updated_at FROM accounts WHERE id = ?", (account_id,)).fetchone()
    if row:
        data = {"id": row[0], "name": row[1], "balance": row[2], "updated_at": row[3]}
        cache[account_id] = data  # 回填快取
        return {**data, "source": "database"}
    return None

# ========== HTTP Server ==========
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/api/account':
            body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            start = time.time()
            result = write_through(body["id"], body["name"], body["balance"])
            elapsed = time.time() - start
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                **result,
                "strategy": "write-through",
                "write_time_ms": round(elapsed * 1000, 2)
            }, indent=2).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        if self.path.startswith('/api/account/'):
            account_id = self.path.split('/')[-1]
            start = time.time()
            result = read_with_cache(account_id)
            elapsed = time.time() - start
            if result:
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({
                    **result,
                    "read_time_ms": round(elapsed * 1000, 2)
                }, indent=2).encode())
            else:
                self.send_response(404)
                self.end_headers()
        elif self.path == '/api/stats':
            total = stats["cache_hits"] + stats["cache_misses"]
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                **stats,
                "hit_ratio": f"{stats['cache_hits']/total:.1%}" if total > 0 else "N/A",
                "cache_size": len(cache)
            }, indent=2).encode())
        elif self.path == '/api/verify':
            # 直接從 DB 讀取，繞過快取，用於驗證一致性
            rows = db.execute("SELECT * FROM accounts").fetchall()
            db_data = {r[0]: {"name": r[1], "balance": r[2]} for r in rows}
            cache_data = {k: {"name": v["name"], "balance": v["balance"]} for k, v in cache.items()}
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                "cache_db_consistent": db_data == cache_data,
                "db_records": len(db_data),
                "cache_records": len(cache_data)
            }, indent=2).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass

print("Write-Through Cache Server at http://localhost:8084")
HTTPServer(('', 8084), Handler).serve_forever()
PYEOF

python3 write_through.py &
WT_PID=$!
sleep 1
```

### 驗證方法

```bash
# 驗證點 1：Write-Through 寫入
echo "=== 寫入帳戶（Write-Through）==="
curl -s -X POST http://localhost:8084/api/account \
  -H "Content-Type: application/json" \
  -d '{"id": "ACC001", "name": "Alice", "balance": 50000}' | python3 -m json.tool

curl -s -X POST http://localhost:8084/api/account \
  -H "Content-Type: application/json" \
  -d '{"id": "ACC002", "name": "Bob", "balance": 30000}' | python3 -m json.tool

# 驗證點 2：讀取（應來自快取）
echo -e "\n=== 讀取帳戶（應從 Cache 讀取）==="
curl -s http://localhost:8084/api/account/ACC001 | python3 -m json.tool

# 驗證點 3：驗證快取與 DB 的一致性
echo -e "\n=== 驗證 Cache 與 DB 一致性 ==="
curl -s http://localhost:8084/api/verify | python3 -m json.tool

# 驗證點 4：更新後再驗證一致性
echo -e "\n=== 更新餘額 ==="
curl -s -X POST http://localhost:8084/api/account \
  -H "Content-Type: application/json" \
  -d '{"id": "ACC001", "name": "Alice", "balance": 45000}' | python3 -m json.tool

echo -e "\n=== 更新後讀取 ==="
curl -s http://localhost:8084/api/account/ACC001 | python3 -m json.tool

echo -e "\n=== 更新後一致性驗證 ==="
curl -s http://localhost:8084/api/verify | python3 -m json.tool

# 清理
kill $WT_PID 2>/dev/null
rm -f data.db
cd ..
```

預期輸出：

```
=== 讀取帳戶（應從 Cache 讀取）===
{
  "id": "ACC001",
  "name": "Alice",
  "balance": 50000,
  "source": "cache",             <-- 從快取讀取
  "read_time_ms": 0.02           <-- 極快
}

=== 驗證 Cache 與 DB 一致性 ===
{
  "cache_db_consistent": true,   <-- Write-Through 保證一致！
  "db_records": 2,
  "cache_records": 2
}
```

### 適用場景

- **銀行帳戶餘額**：餘額必須即時正確
- **庫存數量**：電商即時庫存必須準確
- **用戶權限設定**：安全相關變更必須立即生效

---

## Lab 8：Write-Back Cache（寫回快取）

### 概念

| 項目 | 說明 |
|------|------|
| **運作方式** | 先寫入快取，稍後非同步寫入資料庫 |
| **最適場景** | 高寫入量、對延遲敏感的系統 |
| **核心價值** | 極快的寫入速度 |

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

**風險：** 快取節點崩潰時，未同步的資料可能遺失。

### 實作步驟

```bash
mkdir -p lab8-write-back
cd lab8-write-back

cat > write_back.py << 'PYEOF'
import json, time, sqlite3, threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from collections import defaultdict

# ========== 初始化 ==========
cache = {}
dirty_keys = set()  # 尚未同步到 DB 的 key
db = sqlite3.connect("data_wb.db", check_same_thread=False)
db.execute("CREATE TABLE IF NOT EXISTS page_views (page TEXT PRIMARY KEY, views INT, synced_at TEXT)")
db.commit()
lock = threading.Lock()

stats = {"writes": 0, "flushes": 0, "data_in_flight": 0}

# ========== Write-Back 實作 ==========
def write_back(page, increment=1):
    """只寫入快取，立即返回"""
    with lock:
        if page in cache:
            cache[page] += increment
        else:
            cache[page] = increment
        dirty_keys.add(page)
        stats["writes"] += 1
        stats["data_in_flight"] = len(dirty_keys)
    return cache[page]

def flush_to_db():
    """背景程序：定期將髒資料批次寫入 DB"""
    while True:
        time.sleep(5)  # 每 5 秒同步一次
        with lock:
            if not dirty_keys:
                continue
            keys_to_flush = list(dirty_keys)
            data_to_flush = {k: cache[k] for k in keys_to_flush}
            dirty_keys.clear()

        # 批次寫入 DB（在鎖外執行，避免阻塞寫入）
        timestamp = time.strftime('%H:%M:%S')
        for page, views in data_to_flush.items():
            db.execute(
                "INSERT OR REPLACE INTO page_views (page, views, synced_at) VALUES (?, ?, ?)",
                (page, views, timestamp)
            )
        db.commit()
        stats["flushes"] += 1
        stats["data_in_flight"] = len(dirty_keys)
        print(f"[FLUSH] Synced {len(data_to_flush)} pages to DB at {timestamp}")

# 啟動背景同步
flush_thread = threading.Thread(target=flush_to_db, daemon=True)
flush_thread.start()

# ========== HTTP Server ==========
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path.startswith('/api/pageview/'):
            page = self.path.split('/')[-1]
            start = time.time()
            count = write_back(page)
            elapsed = time.time() - start
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                "page": page,
                "views": count,
                "strategy": "write-back",
                "write_time_ms": round(elapsed * 1000, 4),
                "synced_to_db": page not in dirty_keys
            }).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        if self.path == '/api/stats':
            # 比較快取與 DB 的狀態
            db_rows = db.execute("SELECT page, views FROM page_views").fetchall()
            db_data = {r[0]: r[1] for r in db_rows}
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                "total_writes": stats["writes"],
                "flush_count": stats["flushes"],
                "dirty_keys": len(dirty_keys),
                "cache_state": dict(cache),
                "db_state": db_data,
                "data_loss_risk": list(dirty_keys)
            }, indent=2).encode())
        elif self.path.startswith('/api/pageview/'):
            page = self.path.split('/')[-1]
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                "page": page,
                "views": cache.get(page, 0),
                "source": "cache"
            }).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass

print("Write-Back Cache Server at http://localhost:8085")
print("Flush interval: every 5 seconds")
HTTPServer(('', 8085), Handler).serve_forever()
PYEOF

python3 write_back.py &
WB_PID=$!
sleep 1
```

### 驗證方法

```bash
# 驗證點 1：高速寫入（應極快）
echo "=== 高速寫入 1000 次頁面瀏覽 ==="
START_TIME=$(date +%s%N)
for i in $(seq 1 1000); do
    curl -s -X POST http://localhost:8085/api/pageview/homepage > /dev/null
done
END_TIME=$(date +%s%N)
ELAPSED=$(( (END_TIME - START_TIME) / 1000000 ))
echo "1000 次寫入耗時: ${ELAPSED}ms"

# 模擬多個頁面
for page in about products contact blog; do
    for i in $(seq 1 100); do
        curl -s -X POST http://localhost:8085/api/pageview/$page > /dev/null
    done
done

# 驗證點 2：立即查看狀態（DB 可能還沒同步）
echo -e "\n=== 寫入後立即查看（注意 dirty_keys）==="
curl -s http://localhost:8085/api/stats | python3 -m json.tool

# 驗證點 3：等待背景同步
echo -e "\n等待 6 秒讓背景程序同步..."
sleep 6

echo "=== 同步後查看（dirty_keys 應為空）==="
curl -s http://localhost:8085/api/stats | python3 -m json.tool

# 驗證點 4：展示 Write-Back 的延遲優勢
echo -e "\n=== 單次寫入延遲 ==="
curl -s -X POST http://localhost:8085/api/pageview/latency-test | python3 -m json.tool

# 清理
kill $WB_PID 2>/dev/null
rm -f data_wb.db
cd ..
```

預期輸出：

```
=== 高速寫入 1000 次頁面瀏覽 ===
1000 次寫入耗時: 3200ms         <-- 平均每次 ~3ms（僅寫快取）

=== 寫入後立即查看（注意 dirty_keys）===
{
  "total_writes": 1400,
  "flush_count": 0,
  "dirty_keys": 5,              <-- 尚未同步到 DB！
  "cache_state": {
    "homepage": 1000,
    "about": 100, ...
  },
  "db_state": {},               <-- DB 為空！資料仍在快取中
  "data_loss_risk": ["homepage", "about", ...]   <-- 這些資料有遺失風險
}

=== 同步後查看（dirty_keys 應為空）===
{
  "dirty_keys": 0,              <-- 已全部同步
  "cache_state": {"homepage": 1000, ...},
  "db_state": {"homepage": 1000, ...},    <-- DB 已追上！
  "data_loss_risk": []          <-- 無遺失風險
}

=== 單次寫入延遲 ===
{
  "write_time_ms": 0.0412       <-- 極快！只寫記憶體
}
```

### 適用場景

- **頁面瀏覽計數器**：高頻寫入，少量遺失可接受
- **IoT 感測器數據**：大量寫入，允許批次處理
- **用戶行為日誌**：點擊流、瀏覽記錄等分析數據

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

每一層快取都應該有監控指標：

| 指標 | 說明 | 目標 |
|------|------|------|
| Hit Ratio | 命中率 | > 90% |
| Latency | 回應延遲 | P99 < 10ms |
| Memory Usage | 記憶體使用量 | < 80% capacity |
| Eviction Count | 淘汰次數 | 趨勢穩定 |

### 4. 優雅降級（Graceful Degradation）

快取層失效時，系統應該能夠降級到下一層，而不是直接崩潰。設計 Circuit Breaker 和 Fallback 機制。

### 5. 安全性考量（Security）

快取中可能包含敏感資料（Session Token、個資）。確保快取的存取控制、加密傳輸、以及適當的 TTL 設定。

---

## 全部清理

```bash
# 清理所有 Lab 目錄
rm -rf lab1-browser-cache lab2-cdn-cache lab3-reverse-proxy \
       lab4-app-cache lab5-db-cache lab6-distributed-cache \
       lab7-write-through lab8-write-back
```

---

## 總結

快取不是「加個 Redis 就好」的事情。它是一個**多層次的架構決策**，涉及從前端到資料庫的每一個環節：

| # | 快取類型 | 位置 | 核心場景 |
|---|---------|------|---------|
| 1 | Browser Cache | 瀏覽器 | 靜態資源零延遲 |
| 2 | CDN Cache | 邊緣節點 | 就近回應、保護源站 |
| 3 | Reverse Proxy Cache | NGINX/Varnish | 減輕後端負載 |
| 4 | Application Cache | 應用程式內部 | 避免重複計算 |
| 5 | Database Cache | DB 引擎內部 | 減少磁碟 I/O |
| 6 | Distributed Cache | Redis 叢集 | 微服務共享狀態 |
| 7 | Write-Through | 跨層策略 | 強一致性寫入 |
| 8 | Write-Back | 跨層策略 | 高速寫入 |

理解這 8 種快取類型及其適用場景，能幫助你在系統設計中做出更精確的架構決策。

---

*基於 Rocky Bhatia 的「8 Types of Caching Used in System Design」整理、擴充與實作*
