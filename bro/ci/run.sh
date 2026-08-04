#!/bin/sh
# test/bro/ci — CI-004: the pager's `v` button, driven through the REAL UI path.
# civ.py runs the FULL `jab ls` pager on a pty (pty.fork, the universal/pager.py
# kin) over a seeded worktree carrying a `ci.sh`, then presses `v` with real
# keystrokes and reads the frames back: the run starts, a re-press while it is
# in flight REPORTS instead of respawning, and the verdict badge appears in the
# status bar on its own once the child exits.  RED before the binding lands
# (`v` is an unbound key: no message, no badge, ever).
# Registered by the be/test glob as be-js-bro-ci — no CMakeLists edit.
. "$(dirname "$0")/../lib/brocase.sh"

[ -f "$BROWT/views/bro/pager.js" ] || { echo "bro/ci: SKIP — no pager at $BROWT" >&2; pass; }
[ -f "$BROWT/shared/ci.js" ]       || { echo "bro/ci: SKIP — no shared/ci.js at $BROWT" >&2; pass; }

command -v python3 >/dev/null 2>&1 || { echo "bro/ci: SKIP — no python3" >&2; pass; }
python3 -c "import pty,select" 2>/dev/null || { echo "bro/ci: SKIP — no pty module" >&2; pass; }

# SKIP if the jab build lacks the tty binding (pre-JS-053) — the pager is blocked.
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.raw === "function" &&
           typeof tty.openpty === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo err)
[ "$HAS" = "yes" ] || { echo "bro/ci: SKIP — jab has no tty binding (got '$HAS')" >&2; pass; }

# --- the fixture worktree (the universal/ shape) ---------------------------
. "$_ROOT/lib/repo-setup.sh"
SRC="$WORK/src"
WORKD=$(rs_work_root "$SRC")
ln -sfn "$BROWT" "$SRC/jsrc"
BE_ROOT="$WORK"; export BE_ROOT
FIX="$WORKD/CIV"
mkdir -p "$FIX/.be"
printf 'alpha\n' > "$FIX/hello.txt"
# The detected rung: rung 1 (`./ci.sh`).  It sleeps so the SECOND `v` press
# reliably lands while the child is still in flight.
cat > "$FIX/ci.sh" <<'EOF'
#!/bin/sh
echo CIRAN
sleep 3
exit 0
EOF
chmod +x "$FIX/ci.sh"
( cd "$FIX" && "$JABC" post '#seed' ) >"$WORK/seed.out" 2>"$WORK/seed.err" || {
    echo "--- seed stderr ---"; cat "$WORK/seed.err"; _fail "fixture post failed"; }

# The run artefacts land under $TMP/be-ci (never in the tree) — give the case
# its own so a stale verdict from another run cannot be read as this one's.
CITMP="$WORK/citmp"; mkdir -p "$CITMP"

TMP="$CITMP" python3 "$_CASE/civ.py" "$JABC" "$FIX" >"$WORK/v.out" 2>"$WORK/v.err" || {
    echo "--- stderr ---"; cat "$WORK/v.err"
    echo "--- out ---";    cat "$WORK/v.out"; _fail "pager v-button checks failed"; }
grep -q '^DONE' "$WORK/v.out" || { echo "--- out ---"; cat "$WORK/v.out"; _fail "v-button run did not finish"; }
sed 's/^/     /' "$WORK/v.out"
echo "ok   pager v runs the default build+test and surfaces the verdict"
pass
