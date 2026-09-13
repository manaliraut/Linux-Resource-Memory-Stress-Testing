#!/usr/bin/env python3
"""
Lightweight HTTP server - the victim workload.
Serves a simple endpoint that wrk will benchmark.
"""
from http.server import HTTPServer, BaseHTTPRequestHandler
import time

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'OK\n')

    def log_message(self, format, *args):
        pass  # suppress per-request logs to reduce noise

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8080), Handler)
    print("Server running on port 8080", flush=True)
    server.serve_forever()
