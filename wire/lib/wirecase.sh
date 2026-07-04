#  test/wire/lib/wirecase.sh — shared setup for the GIT-012 jab-GET wire cases
#  (clone/update/incremental over ssh: and http:).  Sourced at the top of each
#  test/wire/<case>/run.sh.  Builds on getcase.sh (which plants the `be ->
#  <worktree>` shard symlink so bareword `jab get` resolves THIS worktree's
#  shared/wire.js — the only place the http: transport exists), then adds:
#    * a SMALL synthetic bare git repo with master + v1.0/v2.0 tags (wire_seed)
#    * a hermetic smart-HTTP `git upload-pack` server (wire_http_up / _down)
#    * tip helpers: wire_tip (recorded wtlog tip) / wire_bare_tip (ref in bare)
#  All-or-nothing SKIP if git/python3/curl/ssh are missing — never a false FAIL.
#  POSIX sh.  No native `be` counterpart for http:, so these are SELF-checking
#  E2E cases (the assertion is tip == bare ref, plus a worktree match vs a
#  reference `git clone`), not parity diffs.

#  getcase.sh: locates be/jab, sets WORK, exports JABC/KEEPER_BIN/DOG_REMOTE_PATH,
#  plants the worktree `be` symlink, and defines _fail/tree_eq/pass.
. "$(dirname "$0")/../../lib/getcase.sh"

command -v git     >/dev/null 2>&1 || { echo "SKIP [$NAME] no git";     exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP [$NAME] no python3"; exit 0; }
command -v curl    >/dev/null 2>&1 || { echo "SKIP [$NAME] no curl";    exit 0; }

#  --- a SMALL synthetic bare repo: master@c2, tags v1.0@c1 v2.0@c2 ----------
#  Sets BARE, REL (HOME-relative for the ssh peer), TIP_V1/TIP_V2 (tag commits).
#  ssh: needs the bare under $HOME (the keeper/git peer resolves HOME-relative);
#  SKIP cleanly otherwise.
wire_seed() {
  BARE="$WORK/repo.git"; SEED="$WORK/seed"
  git init -q --bare -b master "$BARE"
  git init -q -b master "$SEED"
  git -C "$SEED" config user.email t@e.st; git -C "$SEED" config user.name T
  printf 'A\n' > "$SEED/a.txt"; mkdir -p "$SEED/d"; printf 'C\n' > "$SEED/d/c.txt"
  git -C "$SEED" add -A; git -C "$SEED" commit -qm c1; git -C "$SEED" tag v1.0
  printf 'B\n' > "$SEED/b.txt"; printf 'A2\n' > "$SEED/a.txt"
  git -C "$SEED" add -A; git -C "$SEED" commit -qm c2; git -C "$SEED" tag v2.0
  git -C "$SEED" push -q "$BARE" master:master
  git -C "$SEED" push -q "$BARE" --tags
  TIP_V1=$(git -C "$BARE" rev-parse v1.0^{commit})
  TIP_V2=$(git -C "$BARE" rev-parse v2.0^{commit})
  case "$BARE" in
    "$HOME"/*) REL="${BARE#$HOME/}" ;;
    *) echo "SKIP [$NAME] scratch not under \$HOME"; exit 0 ;;
  esac
  #  Reference HEAD (==v2/master) checkout, for the worktree-match assertion.
  REFWT="$WORK/refwt"; git clone -q "$BARE" "$REFWT" >/dev/null 2>&1
}

#  --- hermetic smart-HTTP upload-pack backend over the bare repo ------------
#  wire_http_up <bare> -> sets HURL (http base) + HPID; wire_http_down reaps it.
#  Same shape as test/get/http: GET info/refs (with `# service` preamble) + POST
#  --stateless-rpc, delegating to `git upload-pack`.
wire_http_up() {
  _bare=$1
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
  #  Pick a free-ish port from the pid; retry the bind a few times.
  HPORT=$(( 8600 + ($$ % 800) ))
  i=0; while [ $i -lt 8 ]; do
    : > "$WORK/srv.log"
    python3 "$SRV" "$HPORT" "$_bare" >/dev/null 2>"$WORK/srv.log" &
    HPID=$!
    j=0; while [ $j -lt 50 ]; do
      grep -q up "$WORK/srv.log" 2>/dev/null && break
      kill -0 "$HPID" 2>/dev/null || break
      j=$((j+1)); sleep 0.1
    done
    if grep -q up "$WORK/srv.log" 2>/dev/null; then
      HURL="http://127.0.0.1:$HPORT"; return 0
    fi
    kill "$HPID" 2>/dev/null; HPORT=$((HPORT+1)); i=$((i+1))
  done
  _fail "http backend failed to start (last log: $(cat "$WORK/srv.log" 2>/dev/null))"
}
# PUT-006: EXIT-trap teardown — reap the http server, then (on clean exit only)
# rm the pid scratch getcase.sh minted; keep it on failure for debugging.
wire_http_down() { _rc=$?; kill "$HPID" 2>/dev/null || true
    [ "$_rc" = 0 ] && [ -n "${TMP:-}" ] && rm -rf "$TMP/$$"; return 0; }

#  --- GIT-013/014 PUSH helpers (receive-pack peer + a be-store clone) -------
#  wire_push_seed: a SMALL bare peer (master@A) + a beagle worktree CLONE of it
#  (via ssh://localhost, the only way to build a be store from a git bare here).
#  Sets PBARE (bare path), PREL (HOME-relative), PWT (the be worktree), PA (the
#  seed sha A).  ssh-to-localhost + scratch-under-$HOME are REQUIRED (the keeper
#  wire resolves HOME-relative); SKIP cleanly otherwise — never a false FAIL.
wire_push_seed() {
  command -v ssh >/dev/null 2>&1 || { echo "SKIP [$NAME] no ssh"; exit 0; }
  case "$WORK" in "$HOME"/*) ;; *) echo "SKIP [$NAME] scratch not under \$HOME"; exit 0;; esac
  ssh -o BatchMode=yes -o ConnectTimeout=4 localhost true >/dev/null 2>&1 \
    || { echo "SKIP [$NAME] no passwordless ssh to localhost"; exit 0; }
  PBARE="$WORK/peer.git"; PREL="${PBARE#$HOME/}"
  git init -q --bare -b master "$PBARE"
  git config -f "$PBARE/config" receive.denyCurrentBranch ignore
  git config -f "$PBARE/config" http.receivepack true
  _ps="$WORK/pseed"; git init -q -b master "$_ps"
  git -C "$_ps" config user.email t@e.st; git -C "$_ps" config user.name T
  printf 'A\n' > "$_ps/a.txt"; git -C "$_ps" add -A
  git -C "$_ps" commit -qm A >/dev/null 2>&1
  git -C "$_ps" push -q "$PBARE" master:master >/dev/null 2>&1
  PA=$(git -C "$PBARE" rev-parse master)
  PWT="$WORK/pwt"; rm -rf "$PWT"; mkdir "$PWT"
  ( cd "$PWT" && "$JABC" get "ssh://localhost/$PREL" ) >"$WORK/pget.out" 2>"$WORK/pget.err" \
    || { cat "$WORK/pget.err"; _fail "push-seed: ssh clone of peer failed"; }
}

#  wire_local_commit PWT CONTENT  — edit a.txt to CONTENT, put + post a local FF
#  commit in the be worktree.  Echoes the new cur tip (40-hex).
wire_local_commit() {
  ( cd "$1" && printf '%s' "$2" > a.txt && "$JABC" put a.txt >/dev/null 2>&1 \
      && "$JABC" post '#c' >/dev/null 2>&1 ) || _fail "local commit failed"
  grep -aoE '#[0-9a-f]{40}' "$1/.be/wtlog" 2>/dev/null | tail -1 | tr -d '#'
}

#  wire_peer_advance PBARE CONTENT  — a server-side commit on top of master
#  (parent = master) via a throwaway seed; pushes it so the bare's master moves
#  to a sha that is NOT an ancestor of a divergent local commit.  Echoes the sha.
wire_peer_advance() {
  _as="$WORK/padv"; rm -rf "$_as"; git clone -q "$1" "$_as" >/dev/null 2>&1
  git -C "$_as" config user.email t@e.st; git -C "$_as" config user.name T
  printf 'A\nSERVER\n' > "$_as/a.txt"; git -C "$_as" add -A
  git -C "$_as" commit -qm B >/dev/null 2>&1
  git -C "$_as" push -q origin master:master >/dev/null 2>&1
  git -C "$1" rev-parse master
}

#  wire_http_rp_up <bare> -> RURL (http base) + RPID, a smart-HTTP RECEIVE-pack
#  backend (push).  Shells `git receive-pack --stateless-rpc` for the advert
#  (GET) + the POST (mirrors test/.../githttp_rp.py).  wire_http_rp_down reaps.
wire_http_rp_up() {
  _bare=$1; RSRV="$WORK/rpserver.py"
  cat > "$RSRV" <<'PYEOF'
import http.server, subprocess, sys, socketserver
REPO = sys.argv[2]
def pkt(b): return ("%04x" % (len(b)+4)).encode() + b
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if "/info/refs" not in self.path or "git-receive-pack" not in self.path:
            self.send_error(404); return
        out = subprocess.run(["git","receive-pack","--stateless-rpc",
                              "--advertise-refs",REPO], capture_output=True).stdout
        body = pkt(b"# service=git-receive-pack\n") + b"0000" + out
        self.send_response(200)
        self.send_header("Content-Type",
                         "application/x-git-receive-pack-advertisement")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        if not self.path.endswith("/git-receive-pack"): self.send_error(404); return
        n = int(self.headers.get("Content-Length","0"))
        out = subprocess.run(["git","receive-pack","--stateless-rpc",REPO],
                             input=self.rfile.read(n), capture_output=True).stdout
        self.send_response(200)
        self.send_header("Content-Type","application/x-git-receive-pack-result")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers(); self.wfile.write(out)
socketserver.TCPServer.allow_reuse_address = True
httpd = socketserver.TCPServer(("127.0.0.1", int(sys.argv[1])), H)
sys.stderr.write("up\n"); sys.stderr.flush()
httpd.serve_forever()
PYEOF
  RPORT=$(( 8700 + ($$ % 700) ))
  i=0; while [ $i -lt 8 ]; do
    : > "$WORK/rpsrv.log"
    python3 "$RSRV" "$RPORT" "$_bare" >/dev/null 2>"$WORK/rpsrv.log" &
    RPID=$!
    j=0; while [ $j -lt 50 ]; do
      grep -q up "$WORK/rpsrv.log" 2>/dev/null && break
      kill -0 "$RPID" 2>/dev/null || break
      j=$((j+1)); sleep 0.1
    done
    if grep -q up "$WORK/rpsrv.log" 2>/dev/null; then
      RURL="http://127.0.0.1:$RPORT"; return 0
    fi
    kill "$RPID" 2>/dev/null; RPORT=$((RPORT+1)); i=$((i+1))
  done
  _fail "receive-pack http backend failed to start"
}
# PUT-006: as wire_http_down — reap receive-pack server, rm pid scratch on rc=0.
wire_http_rp_down() { _rc=$?; kill "$RPID" 2>/dev/null || true
    [ "$_rc" = 0 ] && [ -n "${TMP:-}" ] && rm -rf "$TMP/$$"; return 0; }

#  wire_big_mirror SRC -> builds BARE (a big bare repo) + sets WANT (its HEAD)
#  from the real git source tree SRC, with the lone `sha1collisiondetection`
#  gitlink + `.gitmodules` STRIPPED from HEAD's tree.  The full blob/tree closure
#  of HEAD is kept, so the pack is still ~300 MB (a genuine treadmill), but with
#  no submodule the GET checkout does not recurse off-box (sub-fetch over the
#  wire is a GIT-012 follow-up, out of scope).  SKIPs if SRC is absent/unreadable.
wire_big_mirror() {
  _src=$1
  [ -d "$_src/.git" ] || [ -d "$_src/HEAD" ] || { echo "SKIP [$NAME] no $_src"; exit 0; }
  BARE="$WORK/git-big.git"
  SD="$_src/.git"
  git init -q --bare -b master "$BARE" || { echo "SKIP [$NAME] init bare failed"; exit 0; }
  #  Stage HEAD's tree into a scratch index, remove the lone gitlink +
  #  .gitmodules, write the filtered tree, commit it (parentless — still drags
  #  HEAD's whole blob/tree closure into the pack).  GIT_DIR/GIT_INDEX_FILE are
  #  passed PER-COMMAND via `env` (NEVER exported) so they cannot leak into the
  #  later `git upload-pack` server — a leaked GIT_DIR would make upload-pack
  #  serve $_src (WITH the submodule) instead of the filtered bare.
  IDX="$WORK/big.index"; rm -f "$IDX"
  env GIT_DIR="$SD" GIT_INDEX_FILE="$IDX" git read-tree HEAD 2>/dev/null \
    || { echo "SKIP [$NAME] read-tree failed"; exit 0; }
  #  `git rm` on a gitlink is submodule-aware (aborts wanting .gitmodules
  #  staged); drop both entries from the index directly via update-index.
  env GIT_DIR="$SD" GIT_INDEX_FILE="$IDX" git update-index --force-remove \
    sha1collisiondetection .gitmodules 2>/dev/null || true
  _tree=$(env GIT_DIR="$SD" GIT_INDEX_FILE="$IDX" git write-tree)
  _commit=$(printf 'big treadmill snapshot\n' | \
    env GIT_DIR="$SD" git -c user.email=t@e.st -c user.name=T commit-tree "$_tree")
  [ -n "$_commit" ] || { echo "SKIP [$NAME] commit-tree failed"; exit 0; }
  #  Land the commit's full object closure into the bare via a pack push.
  git --git-dir="$SD" push -q "$BARE" "$_commit:refs/heads/master" 2>/dev/null \
    || { echo "SKIP [$NAME] seed push failed"; exit 0; }
  git -C "$BARE" symbolic-ref HEAD refs/heads/master
  WANT=$(git -C "$BARE" rev-parse HEAD)
  #  Guard: the filtered bare HEAD must carry NO gitlink (else the GET would
  #  recurse off-box into the unreachable github submodule).
  [ "$(git -C "$BARE" ls-tree -r HEAD | grep -c '^160000')" = "0" ] \
    || _fail "big fixture HEAD still has a gitlink (sub strip failed)"
  case "$BARE" in "$HOME"/*) REL="${BARE#$HOME/}";; *) echo "SKIP [$NAME] not under \$HOME"; exit 0;; esac
}

#  wire_tip DIR — the 40-hex commit tip recorded in DIR/.be/wtlog by jab get.
wire_tip() { grep -aoE '#[0-9a-f]{40}' "$1/.be/wtlog" 2>/dev/null | tail -1 | tr -d '#'; }

#  wire_match WT — assert WT's content tree (sans .be/.git) == REFWT (==HEAD).
wire_match() {
  _flt='^\./(\.be(/|$)|\.\.be\.idx$|\.git/)'
  _a=$(cd "$REFWT" && find . -type f | grep -vE "$_flt" | sort)
  _b=$(cd "$1"     && find . -type f | grep -vE "$_flt" | sort)
  [ "$_a" = "$_b" ] || { echo "--- ref ---"; echo "$_a"; echo "--- got ---"; echo "$_b"; _fail "worktree file set differs"; }
  for _f in $_a; do cmp -s "$REFWT/$_f" "$1/$_f" || _fail "worktree content differs: $_f"; done
}
