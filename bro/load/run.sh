#!/bin/sh
# test/bro/load — BRO-034: the pager's LOADING address bar, driven through the
# REAL UI path.  load.py runs the FULL `jab ls` pager on a pty (pty.fork, the
# bro/ci kin) over a worktree holding a few thousand files, then types a
# deliberately SLOW spell and reads the frames back: the bar goes black-on-pale-
# yellow BEFORE the verb runs (still yellow while it runs), and is back to the
# ordinary inverse bar once the view — or the error / no-hunks note — lands.
# Also covers `R` refresh and `-` back replay.  RED before the paint lands (the
# yellow bar is never written at all).
# Registered by the be/test glob as be-js-bro-load — the TIMEOUT rides
# test/CMakeLists.txt beside the other pty pager sessions.
. "$(dirname "$0")/../lib/brocase.sh"

[ -f "$BROWT/views/bro/pager.js" ] || { echo "bro/load: SKIP — no pager at $BROWT" >&2; pass; }
[ -f "$BROWT/view/theme.js" ]      || { echo "bro/load: SKIP — no view/theme.js at $BROWT" >&2; pass; }

command -v python3 >/dev/null 2>&1 || { echo "bro/load: SKIP — no python3" >&2; pass; }
python3 -c "import pty,select,termios,fcntl" 2>/dev/null || { echo "bro/load: SKIP — no pty module" >&2; pass; }

# SKIP if the jab build lacks the tty binding (pre-JS-053) — the pager is blocked.
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.raw === "function" &&
           typeof tty.openpty === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo err)
[ "$HAS" = "yes" ] || { echo "bro/load: SKIP — jab has no tty binding (got '$HAS')" >&2; pass; }

# --- the fixture worktree (the universal/ shape) ---------------------------
. "$_ROOT/lib/repo-setup.sh"
SRC="$WORK/src"
WORKD=$(rs_work_root "$SRC")
ln -sfn "$BROWT" "$SRC/jsrc"
BE_ROOT="$WORK"; export BE_ROOT
FIX="$WORKD/LOAD"
mkdir -p "$FIX/.be"
printf 'alpha\n' > "$FIX/hello.txt"
( cd "$FIX" && "$JABC" post '#seed' ) >"$WORK/seed.out" 2>"$WORK/seed.err" || {
    echo "--- seed stderr ---"; cat "$WORK/seed.err"; _fail "fixture post failed"; }

# The SLOW verb is a real `grep` over a real tree — no fake sleep, no timer.  A
# few thousand small files put the in-process search well past the pty reader's
# poll, so the yellow bar is observable while the search is still running.  They
# are planted AFTER the seed post, so they stay unstaged and the post stays cheap.
python3 - "$FIX" <<'EOF'
import os, sys
d = os.path.join(sys.argv[1], "big")
os.makedirs(d, exist_ok=True)
for i in range(6000):
    with open(os.path.join(d, "f%04d.txt" % i), "w") as f:
        f.write("alpha needle %d\nbeta gamma delta epsilon\nzeta eta theta iota\n" % i)
EOF

python3 "$_CASE/load.py" "$JABC" "$FIX" >"$WORK/l.out" 2>"$WORK/l.err" || {
    echo "--- stderr ---"; cat "$WORK/l.err"
    echo "--- out ---";    cat "$WORK/l.out"; _fail "pager loading-bar checks failed"; }
grep -q '^DONE' "$WORK/l.out" || { echo "--- out ---"; cat "$WORK/l.out"; _fail "loading-bar session did not finish"; }
sed 's/^/     /' "$WORK/l.out"
echo "ok   the address bar goes yellow for every pager-driven load and clears after"
pass
