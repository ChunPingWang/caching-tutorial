"""
Lab 8: Write-Back (Write-Behind) Cache Server
先寫入快取立即回應，背景非同步批次寫入資料庫
展示高速寫入 vs 資料遺失風險的取捨
"""
import json
import time
import sqlite3
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler

# ========== 初始化 ==========
cache = {}
dirty_keys = set()  # 尚未同步到 DB 的 key
lock = threading.Lock()

db = sqlite3.connect("write_back.db", check_same_thread=False)
db.execute("""
    CREATE TABLE IF NOT EXISTS page_views (
        page TEXT PRIMARY KEY,
        views INTEGER,
        synced_at TEXT
    )
""")
db.commit()

stats = {
    "total_writes": 0,
    "flush_count": 0,
    "items_flushed": 0,
    "last_flush_at": None
}


# ========== Write-Back 核心邏輯 ==========
def write_back(page, increment=1):
    """只寫入快取，立即返回 (超快！)"""
    with lock:
        if page in cache:
            cache[page] += increment
        else:
            cache[page] = increment
        dirty_keys.add(page)
        stats["total_writes"] += 1
    return cache[page]


def flush_to_db():
    """背景執行緒: 每 5 秒批次同步髒資料到 DB"""
    while True:
        time.sleep(5)
        with lock:
            if not dirty_keys:
                continue
            keys_to_flush = list(dirty_keys)
            data_to_flush = {k: cache[k] for k in keys_to_flush}
            dirty_keys.clear()

        # 批次寫入 DB (在鎖外執行)
        timestamp = time.strftime('%H:%M:%S')
        for page, views in data_to_flush.items():
            db.execute(
                "INSERT OR REPLACE INTO page_views (page, views, synced_at) VALUES (?, ?, ?)",
                (page, views, timestamp)
            )
        db.commit()

        stats["flush_count"] += 1
        stats["items_flushed"] += len(data_to_flush)
        stats["last_flush_at"] = timestamp
        print(f"[FLUSH #{stats['flush_count']}] Synced {len(data_to_flush)} pages to DB at {timestamp}")


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
            self._json_response(200, {
                "page": page,
                "views": count,
                "strategy": "write-back",
                "write_time_ms": round(elapsed * 1000, 4),
                "synced_to_db": page not in dirty_keys
            })
        else:
            self._json_response(404, {"error": "not found"})

    def do_GET(self):
        if self.path == '/api/stats':
            db_rows = db.execute("SELECT page, views, synced_at FROM page_views").fetchall()
            db_data = {r[0]: {"views": r[1], "synced_at": r[2]} for r in db_rows}
            self._json_response(200, {
                **stats,
                "dirty_keys_count": len(dirty_keys),
                "dirty_keys": list(dirty_keys),
                "cache_state": dict(cache),
                "db_state": db_data,
                "data_loss_risk_keys": list(dirty_keys)
            })

        elif self.path.startswith('/api/pageview/'):
            page = self.path.split('/')[-1]
            self._json_response(200, {
                "page": page,
                "views": cache.get(page, 0),
                "source": "cache",
                "is_dirty": page in dirty_keys
            })

        elif self.path == '/api/compare':
            # 比較快取與 DB 的差異
            db_rows = db.execute("SELECT page, views FROM page_views").fetchall()
            db_data = {r[0]: r[1] for r in db_rows}
            differences = []
            for key in set(list(cache.keys()) + list(db_data.keys())):
                c_val = cache.get(key, "NOT IN CACHE")
                d_val = db_data.get(key, "NOT IN DB")
                if c_val != d_val:
                    differences.append({
                        "page": key,
                        "cache_views": c_val,
                        "db_views": d_val,
                        "is_dirty": key in dirty_keys
                    })
            self._json_response(200, {
                "total_keys": len(set(list(cache.keys()) + list(db_data.keys()))),
                "consistent_keys": len(set(list(cache.keys()) + list(db_data.keys()))) - len(differences),
                "inconsistent_keys": len(differences),
                "differences": differences
            })
        else:
            self._json_response(404, {"error": "not found"})

    def _json_response(self, status, data):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data, indent=2).encode())

    def log_message(self, fmt, *args):
        pass


if __name__ == '__main__':
    port = 8085
    print(f"=== Write-Back Cache Lab Server ===")
    print(f"URL: http://localhost:{port}")
    print(f"Flush interval: every 5 seconds")
    print(f"策略: 先寫快取, 背景非同步寫 DB")
    HTTPServer(('', port), Handler).serve_forever()
