"""Feature Engineering service - minimal skeleton for Docker build verification."""

import os
from http.server import HTTPServer, BaseHTTPRequestHandler


class HealthCheckHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok")
        else:
            self.send_response(404)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"not found")

    def log_message(self, format, *args):
        print(f"[feature-engineering] {args[0]}")


def main():
    port = int(os.environ.get("PORT", "8080"))
    server = HTTPServer(("0.0.0.0", port), HealthCheckHandler)
    print(f"Feature Engineering starting on port {port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
