"""
Lab 2: CDN 源站模擬
模擬一個有延遲的源站，讓 NGINX 邊緣快取發揮作用
"""
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import time


class OriginHandler(BaseHTTPRequestHandler):
    request_count = 0

    def do_GET(self):
        OriginHandler.request_count += 1
        # 模擬源站處理延遲
        time.sleep(0.5)

        if self.path == '/api/exchange-rate':
            data = {
                "currency": "USD/TWD",
                "rate": "31.25",
                "timestamp": time.strftime('%H:%M:%S'),
                "source": "origin-server",
                "origin_request_count": OriginHandler.request_count
            }
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'public, max-age=15')
            self.end_headers()
            self.wfile.write(json.dumps(data, indent=2).encode())
        elif self.path == '/api/product-image':
            data = {
                "image_url": "/images/product-001.jpg",
                "size": "1.2MB",
                "timestamp": time.strftime('%H:%M:%S'),
                "source": "origin-server",
                "origin_request_count": OriginHandler.request_count
            }
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'public, max-age=86400')
            self.end_headers()
            self.wfile.write(json.dumps(data, indent=2).encode())
        else:
            content = f'{{"path": "{self.path}", "time": "{time.strftime("%H:%M:%S")}", "source": "origin", "count": {OriginHandler.request_count}}}'
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'public, max-age=15')
            self.end_headers()
            self.wfile.write(content.encode())

    def log_message(self, fmt, *args):
        print(f"[ORIGIN #{OriginHandler.request_count}] {args[0]} at {time.strftime('%H:%M:%S')}")


if __name__ == '__main__':
    print("CDN Origin Server running on port 8000")
    HTTPServer(('', 8000), OriginHandler).serve_forever()
