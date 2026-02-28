"""
Lab 7: Write-Through Cache Server
寫入時同時更新快取與資料庫，兩者都成功才回應客戶端
確保快取與 DB 的強一致性
"""
import json
import time
import sqlite3
from http.server import HTTPServer, BaseHTTPRequestHandler

# ========== 初始化 ==========
cache = {}  # In-memory cache
db = sqlite3.connect("write_through.db", check_same_thread=False)
db.execute("""
    CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        name TEXT,
        balance REAL,
        updated_at TEXT
    )
""")
db.commit()

stats = {"cache_hits": 0, "cache_misses": 0, "writes": 0, "read_count": 0}


# ========== Write-Through 核心邏輯 ==========
def write_through(account_id, name, balance):
    """
    Write-Through: 同步寫入 Cache + DB
    兩者都成功才返回
    """
    timestamp = time.strftime('%H:%M:%S')
    data = {
        "id": account_id,
        "name": name,
        "balance": balance,
        "updated_at": timestamp
    }

    # Step 1: 寫入 DB (先寫 DB 確保持久化)
    db.execute(
        "INSERT OR REPLACE INTO accounts (id, name, balance, updated_at) VALUES (?, ?, ?, ?)",
        (account_id, name, balance, timestamp)
    )
    db.commit()

    # Step 2: 寫入 Cache
    cache[account_id] = data

    stats["writes"] += 1
    return data


def read_account(account_id):
    """讀取: 先查快取, 未命中才查 DB"""
    stats["read_count"] += 1

    if account_id in cache:
        stats["cache_hits"] += 1
        return {**cache[account_id], "source": "cache"}

    stats["cache_misses"] += 1
    row = db.execute(
        "SELECT id, name, balance, updated_at FROM accounts WHERE id = ?",
        (account_id,)
    ).fetchone()
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
            self._json_response(200, {
                **result,
                "strategy": "write-through",
                "write_time_ms": round(elapsed * 1000, 2)
            })
        else:
            self._json_response(404, {"error": "not found"})

    def do_GET(self):
        if self.path.startswith('/api/account/'):
            account_id = self.path.split('/')[-1]
            start = time.time()
            result = read_account(account_id)
            elapsed = time.time() - start
            if result:
                self._json_response(200, {
                    **result,
                    "read_time_ms": round(elapsed * 1000, 4)
                })
            else:
                self._json_response(404, {"error": f"Account {account_id} not found"})

        elif self.path == '/api/stats':
            total_reads = stats["cache_hits"] + stats["cache_misses"]
            self._json_response(200, {
                **stats,
                "hit_ratio": f"{stats['cache_hits']/total_reads:.1%}" if total_reads > 0 else "N/A",
                "cache_size": len(cache)
            })

        elif self.path == '/api/verify':
            # 直接讀 DB, 與快取比較
            rows = db.execute("SELECT id, name, balance FROM accounts").fetchall()
            db_data = {r[0]: {"name": r[1], "balance": r[2]} for r in rows}
            cache_data = {k: {"name": v["name"], "balance": v["balance"]} for k, v in cache.items()}
            consistent = db_data == cache_data
            self._json_response(200, {
                "cache_db_consistent": consistent,
                "db_records": len(db_data),
                "cache_records": len(cache_data),
                "mismatches": [] if consistent else [
                    k for k in set(list(db_data.keys()) + list(cache_data.keys()))
                    if db_data.get(k) != cache_data.get(k)
                ]
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
    port = 8084
    print(f"=== Write-Through Cache Lab Server ===")
    print(f"URL: http://localhost:{port}")
    print(f"策略: 寫入同時更新 Cache + DB")
    HTTPServer(('', port), Handler).serve_forever()
