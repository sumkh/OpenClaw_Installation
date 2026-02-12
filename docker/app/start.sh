#!/bin/bash
set -euo pipefail

echo "[openclaw-start] Starting OpenClaw placeholder application..."

# Print key environment values (safe to show variable names only)
echo "OPENCLAW_HOME=${OPENCLAW_HOME:-/opt/openclaw}"
echo "GOOGLE_APPLICATION_CREDENTIALS=${GOOGLE_APPLICATION_CREDENTIALS:-not set}"
echo "WHATSAPP_CRED_FILE=${WHATSAPP_CRED_FILE:-not set}"

PORT=${OPENCLAW_PORT:-8080}

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found in image — install python3 or replace start script with the real OpenClaw runtime." >&2
  sleep infinity
fi

echo "Listening on port $PORT (health: /health)"

python3 - <<'PY'
from http.server import HTTPServer, BaseHTTPRequestHandler
import json, os

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            resp = {'status': 'ok', 'service': 'openclaw-placeholder'}
            self.wfile.write(json.dumps(resp).encode())
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'Not found')
    def log_message(self, format, *args):
        return

if __name__ == '__main__':
    port = int(os.environ.get('OPENCLAW_PORT', '8080'))
    server = HTTPServer(('0.0.0.0', port), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
PY
