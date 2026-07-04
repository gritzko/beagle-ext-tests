#!/bin/sh
# GIT-012: test/get/http — `jab get http://…` over the smart-HTTP curl
# transport (no native `be` counterpart, so this is a SELF-checking E2E, not a
# parity diff).  A hermetic python3 server wraps `git upload-pack` (advert +
# --stateless-rpc); we clone it with `jab get` and assert the checked-out tree
# matches the source repo.  Needs git + python3 + curl; SKIPs cleanly if any
# is absent.
. "$(dirname "$0")/../../lib/getcase.sh"

command -v git     >/dev/null 2>&1 || { echo "SKIP [http] no git";     exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP [http] no python3"; exit 0; }
command -v curl    >/dev/null 2>&1 || { echo "SKIP [http] no curl";    exit 0; }

REPO="$WORK/repo"
mkdir -p "$REPO"; ( cd "$REPO"
  git init -q
  git config user.email t@e.st; git config user.name Test
  printf 'A\n' > a.txt; printf 'B\n' > b.txt
  mkdir d; printf 'C\n' > d/c.txt
  git add -A; git commit -qm c1 ) >/dev/null 2>&1

# Hermetic smart-HTTP server: GET info/refs (with `# service` preamble) +
# POST stateless-rpc, both delegating to `git upload-pack <repo>`.
SRV="$WORK/server.py"
cat > "$SRV" <<'PYEOF'
import http.server, subprocess, sys, socketserver
REPO = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        out = subprocess.run(["git","upload-pack","--advertise-refs",REPO],
                             capture_output=True).stdout
        pre = b"# service=git-upload-pack\n"
        body = ("%04x" % (len(pre)+4)).encode() + pre + b"0000" + out
        self.send_response(200)
        self.send_header("Content-Type",
                         "application/x-git-upload-pack-advertisement")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        n = int(self.headers.get("Content-Length","0"))
        req = self.rfile.read(n)
        out = subprocess.run(["git","upload-pack","--stateless-rpc",REPO],
                             input=req, capture_output=True).stdout
        self.send_response(200)
        self.send_header("Content-Type","application/x-git-upload-pack-result")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers(); self.wfile.write(out)
socketserver.TCPServer.allow_reuse_address = True
port = int(sys.argv[1])
httpd = socketserver.TCPServer(("127.0.0.1", port), H)
sys.stderr.write("up\n"); sys.stderr.flush()
httpd.serve_forever()
PYEOF

PORT=8731
python3 "$SRV" "$PORT" "$REPO" >/dev/null 2>"$WORK/srv.log" &
SRVPID=$!
# PUT-006: reap the server, then rm getcase.sh's pid scratch on clean exit (0);
# keep it on failure for debugging (merged into this trap, not a 2nd EXIT trap).
trap 'rc=$?; kill "$SRVPID" 2>/dev/null; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT INT TERM
# Wait for the listener (the python prints "up" after bind).
i=0; while [ $i -lt 50 ]; do
  grep -q up "$WORK/srv.log" 2>/dev/null && break
  i=$((i+1)); sleep 0.1
done

REMOTE="http://127.0.0.1:$PORT/repo?/repo"
mkdir "$WORK/jT"
( cd "$WORK/jT" && "$JABC" get "$REMOTE" ) >"$WORK/jT.out" 2>"$WORK/jT.err" \
  || { echo "--- jab err ---"; cat "$WORK/jT.err"; _fail "jab get http failed"; }

# Assert the checked-out tree matches the source repo (content files only).
for f in a.txt b.txt d/c.txt; do
  [ -f "$WORK/jT/$f" ] || _fail "missing $f in http clone"
  cmp -s "$REPO/$f" "$WORK/jT/$f" || _fail "content differs: $f"
done

pass
