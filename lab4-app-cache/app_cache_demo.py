"""
Lab 4: Application Cache Server
展示 LRU 快取、TTL 過期、快取淘汰（Eviction）行為
"""
import time
import threading
from collections import OrderedDict
from http.server import HTTPServer, BaseHTTPRequestHandler
import json


class LRUCache:
    """帶有 TTL 的 LRU (Least Recently Used) 快取"""

    def __init__(self, capacity=5, ttl_seconds=15):
        self.capacity = capacity
        self.ttl = ttl_seconds
        self.cache = OrderedDict()  # key -> (value, timestamp)
        self.stats = {"hits": 0, "misses": 0, "evictions": 0, "expirations": 0}
        self.lock = threading.Lock()

    def get(self, key):
        with self.lock:
            if key in self.cache:
                value, timestamp = self.cache[key]
                if time.time() - timestamp < self.ttl:
                    self.cache.move_to_end(key)
                    self.stats["hits"] += 1
                    return value
                else:
                    # TTL 過期
                    del self.cache[key]
                    self.stats["expirations"] += 1
            self.stats["misses"] += 1
            return None

    def put(self, key, value):
        with self.lock:
            if key in self.cache:
                del self.cache[key]
            elif len(self.cache) >= self.capacity:
                evicted_key, _ = self.cache.popitem(last=False)
                self.stats["evictions"] += 1
                print(f"[EVICT] Key '{evicted_key}' evicted (LRU)")
            self.cache[key] = (value, time.time())

    def keys(self):
        with self.lock:
            return list(self.cache.keys())

    def size(self):
        with self.lock:
            return len(self.cache)

    def hit_ratio(self):
        total = self.stats["hits"] + self.stats["misses"]
        return self.stats["hits"] / total if total > 0 else 0


def expensive_db_query(product_id):
    """模擬需要 500ms 的資料庫查詢"""
    time.sleep(0.5)
    products = {
        "1": {"name": "MacBook Pro 16", "price": 79900},
        "2": {"name": "iPhone 16 Pro", "price": 39900},
        "3": {"name": "iPad Air", "price": 22900},
        "4": {"name": "Apple Watch", "price": 13900},
        "5": {"name": "AirPods Max", "price": 18900},
        "6": {"name": "Mac Mini M4", "price": 19900},
        "7": {"name": "Studio Display", "price": 47900},
        "8": {"name": "Magic Keyboard", "price": 3490},
    }
    p = products.get(str(product_id), {"name": f"Product-{product_id}", "price": 999})
    return {
        "id": product_id,
        **p,
        "computed_at": time.strftime('%H:%M:%S')
    }


# 初始化快取 (容量=5, TTL=15秒)
cache = LRUCache(capacity=5, ttl_seconds=15)


class AppHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/api/product/'):
            product_id = self.path.split('/')[-1]
            start = time.time()

            result = cache.get(f"product:{product_id}")
            cache_hit = result is not None

            if not cache_hit:
                result = expensive_db_query(product_id)
                cache.put(f"product:{product_id}", result)

            elapsed = time.time() - start
            response = {
                **result,
                "cache_hit": cache_hit,
                "response_time_ms": round(elapsed * 1000, 2),
                "cache_hit_ratio": f"{cache.hit_ratio():.1%}"
            }
            self._json_response(200, response)

        elif self.path == '/api/cache/stats':
            self._json_response(200, {
                "hits": cache.stats["hits"],
                "misses": cache.stats["misses"],
                "evictions": cache.stats["evictions"],
                "expirations": cache.stats["expirations"],
                "hit_ratio": f"{cache.hit_ratio():.1%}",
                "cached_items": cache.size(),
                "capacity": cache.capacity,
                "ttl_seconds": cache.ttl,
                "cached_keys": cache.keys()
            })

        elif self.path == '/api/cache/clear':
            cache.cache.clear()
            cache.stats = {"hits": 0, "misses": 0, "evictions": 0, "expirations": 0}
            self._json_response(200, {"message": "Cache cleared"})

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
    port = 8083
    print(f"=== Application Cache Lab Server ===")
    print(f"URL: http://localhost:{port}")
    print(f"LRU Capacity: {cache.capacity}, TTL: {cache.ttl}s")
    print(f"")
    print(f"端點:")
    print(f"  GET /api/product/{{id}}  - 查詢商品 (帶快取)")
    print(f"  GET /api/cache/stats    - 查看快取統計")
    print(f"  GET /api/cache/clear    - 清空快取")
    HTTPServer(('', port), AppHandler).serve_forever()
