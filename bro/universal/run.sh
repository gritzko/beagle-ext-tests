#!/bin/sh
# test/js/bro/universal — JAB-030 the UNIVERSAL pager front.  Every jab view
# renders its hunk stream through ONE output gate: on a TTY the interactive bro
# Pager, on a PIPE the plain hunk dump.  A pty harness (pager.py, pty.fork) runs
# the FULL `jab <cmd>` over a worktree both ways and asserts the gate picks the
# render — a content view (cat/grep, the hunk sink) AND a columnar view (ls, the
# emit sink wrapped as one hunk).  SKIP-guarded like the other bro cases.
. "$(dirname "$0")/../lib/brocase.sh"

# Needs the JAB-030 loop edge (the universal pager) in $BROWT — gate on the
# landed pager + the hunksFromLog export the edge drives.
[ -f "$BROWT/views/bro/pager.js" ] || { echo "universal: SKIP — no pager at $BROWT" >&2; pass; }
grep -q 'hunksFromLog' "$BROWT/views/bro/pager.js" 2>/dev/null || {
    echo "universal: SKIP — pager lacks hunksFromLog (pre-JAB-030 $BROWT)" >&2; pass; }
grep -q 'wantPager' "$BROWT/core/loop.js" 2>/dev/null || {
    echo "universal: SKIP — loop.js lacks the universal-pager edge (pre-JAB-030)" >&2; pass; }

# The harness needs python3 with the pty module (a controlling-terminal driver).
command -v python3 >/dev/null 2>&1 || { echo "universal: SKIP — no python3" >&2; pass; }
python3 -c "import pty,select" 2>/dev/null || { echo "universal: SKIP — no pty module" >&2; pass; }

# SKIP if the jab build lacks the tty binding (pre-JS-053) — the pager is blocked.
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.raw === "function" &&
           typeof tty.openpty === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo err)
[ "$HAS" = "yes" ] || { echo "universal: SKIP — jab has no tty binding (got '$HAS')" >&2; pass; }

python3 "$_CASE/pager.py" "$JABC" "$BROWT" >"$WORK/u.out" 2>"$WORK/u.err" || {
    echo "--- stderr ---"; cat "$WORK/u.err"
    echo "--- out ---";    cat "$WORK/u.out"; _fail "universal pager checks failed"; }
grep -q '^DONE' "$WORK/u.out" || { echo "--- out ---"; cat "$WORK/u.out"; _fail "universal did not finish"; }
sed 's/^/     /' "$WORK/u.out" | grep '^     ok' >/dev/null && echo "ok   universal pager (tty pager / pipe dump, cat+grep+ls)"
pass
