"""Hypothesis Lab service - minimal skeleton for Docker build verification."""

import os
from http.server import HTTPServer, BaseHTTPRequestHandler
import json


class HealthCheckHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok")
        else:
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            response = {"service": "hypothesis-lab", "status": "running"}
            self.wfile.write(json.dumps(response).encode())

    def log_message(self, format, *args):
        print(f"[hypothesis-lab] {args[0]}")


def main():
    port = int(os.environ.get("PORT", "8080"))
    server = HTTPServer(("0.0.0.0", port), HealthCheckHandler)
    print(f"Hypothesis Lab starting on port {port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
