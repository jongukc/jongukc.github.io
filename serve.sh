#!/bin/sh
# Build the site and preview it at http://localhost:PORT. Sources are rebuilt
# whenever they change (make runs once a second), and the CV is typeset whenever
# a file under cv/ is newer than the PDF; reload the browser to see it.
# Unknown paths get build/404.html with status 404, as on GitHub Pages.
#
#   ./serve.sh [port]      default port: 4000

set -e
port=${1:-4000}
cd "$(dirname "$0")"

make
python3 - "$port" <<'PY' &
import http.server, os, sys

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory="build", **kwargs)

    def send_error(self, code, message=None, explain=None):
        try:
            if code != 404:
                raise FileNotFoundError
            body = open(os.path.join(self.directory, "404.html"), "rb").read()
        except OSError:
            return super().send_error(code, message, explain)
        self.send_response(code)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
PY
server=$!
trap 'kill $server 2>/dev/null' EXIT
trap 'exit' INT TERM
echo "Serving http://localhost:$port (Ctrl-C to stop)"
cv_pdf=files/cv-jonguk.pdf
cv_outdated() { [ ! -e "$cv_pdf" ] || [ -n "$(find cv -newer "$cv_pdf")" ]; }
while sleep 1; do
  if cv_outdated; then make -s cv || sleep 4; fi
  make -s || sleep 4
done
