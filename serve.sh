#!/bin/sh
# Build the site and preview it at http://localhost:PORT. Sources are rebuilt
# whenever they change (make runs once a second); reload the browser to see it.
#
#   ./serve.sh [port]      default port: 4000

set -e
port=${1:-4000}
cd "$(dirname "$0")"

make
python3 -m http.server "$port" --directory build --bind 127.0.0.1 &
server=$!
trap 'kill $server 2>/dev/null' EXIT
trap 'exit' INT TERM
echo "Serving http://localhost:$port (Ctrl-C to stop)"
while sleep 1; do make -s || sleep 4; done
