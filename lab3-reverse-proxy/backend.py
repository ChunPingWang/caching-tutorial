"""
Lab 3: 後端 API Server
模擬有延遲的後端服務，展示反向代理快取的效果
"""
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import time

request_count = 0


class BackendHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global request_count
        request_count += 1
        time.sleep(0.3)  # 模擬 DB 查詢延遲

        if self.path == '/api/v1/products':
            data = {
                "products": [
                    {"id": 1, "name": "MacBook Pro", "price": 59900, "category": "Electronics"},
                    {"id": 2, "name": "iPhone 16", "price": 35900, "category": "Electronics"},
                    {"id": 3, "name": "AirPods Pro", "price": 7490, "category": "Audio"},
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
            self.wfile.write(json.dumps({
                "status": "ok",
                "requests_served": request_count
            }).encode())
        elif self.path.startswith('/api/v1/product/'):
            pid = self.path.split('/')[-1]
            data = {
                "id": pid,
                "name": f"Product-{pid}",
                "price": int(pid) * 1000 if pid.isdigit() else 0,
                "generated_at": time.strftime('%H:%M:%S'),
                "backend_request_count": request_count
            }
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(data, indent=2).encode())
        else:
            self.send_response(404)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"error": "not found"}).encode())

    def log_message(self, fmt, *args):
        print(f"[BACKEND #{request_count}] {args[0]}")


if __name__ == '__main__':
    print("Backend API Server running on port 8000")
    HTTPServer(('', 8000), BackendHandler).serve_forever()
