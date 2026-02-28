"""
Lab 1: Browser Cache Server
啟動方式: python3 cache_server.py
功能: 展示 Cache-Control, ETag, 304 Not Modified 行為
"""
from http.server import HTTPServer, SimpleHTTPRequestHandler
import hashlib
import os


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
            etag = hashlib.md5(
                f"{stat.st_mtime}-{stat.st_size}".encode()
            ).hexdigest()
            self.send_header('ETag', f'"{etag}"')

        super().end_headers()

    def do_GET(self):
        # 處理條件式請求（If-None-Match）
        path = self.translate_path(self.path)
        if os.path.isfile(path):
            stat = os.stat(path)
            etag = hashlib.md5(
                f"{stat.st_mtime}-{stat.st_size}".encode()
            ).hexdigest()
            if self.headers.get('If-None-Match') == f'"{etag}"':
                self.send_response(304)
                self.end_headers()
                return

        super().do_GET()


if __name__ == '__main__':
    port = 8080
    server = HTTPServer(('', port), CacheHandler)
    print(f"=== Browser Cache Lab Server ===")
    print(f"URL: http://localhost:{port}")
    print(f"")
    print(f"快取策略:")
    print(f"  HTML  -> Cache-Control: no-cache (每次重新驗證)")
    print(f"  JS/CSS/SVG -> Cache-Control: public, max-age=3600")
    print(f"  所有資源 -> ETag (支援 304 Not Modified)")
    print(f"")
    print(f"驗證方式:")
    print(f"  1. 開啟瀏覽器 DevTools > Network tab")
    print(f"  2. 訪問 http://localhost:{port}")
    print(f"  3. F5 重新整理觀察 (from cache) 或 304")
    print(f"  4. Ctrl+Shift+R Hard Refresh 觀察全部 200")
    print(f"")
    print(f"按 Ctrl+C 停止 server")
    server.serve_forever()
