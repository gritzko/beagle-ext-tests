#!/bin/sh
# test/js/bro/table — JAB-003 TABLE-record ingest in lib/bro.js.  Drives
# driver.js (which requires lib/bro.js) to build a hunk of {uri,verb,ts} rows
# via JAB-002's feedRow, render plain + colour through the binding's C THEME,
# and assert the row text + that colour carries SGR.  SKIP-guarded: if the
# local `jab` predates JAB-002 (no feedRow), exit 0 — this case only repros
# once the feed API is present (it is, in the current build).
. "$(dirname "$0")/../lib/brocase.sh"

# JAB-bro: the render lib stays at view/bro.js (untouched by the relocation);
# point at the worktree's copy (the same be-relative lib the handler requires).
LIB="${LIB:-$BROWT/view/bro.js}"
[ -f "$LIB" ] || { echo "table: SKIP — no view/bro.js at $BROWT" >&2; pass; }

# SKIP if feedRow is absent (JAB-002 not yet in this jab build).
cat > "$WORK/probe.js" <<'EOF'
"use strict";
const log = abc.ram("HUNK", 4096);
const b = io.buf(64);
b.feed(utf8.Encode(typeof log.feedRow === "function" ? "yes" : "no"));
io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/probe.js" 2>/dev/null || echo err)
[ "$HAS" = "yes" ] || { echo "table: SKIP — jab has no hunk.feedRow (JAB-002 pending: got '$HAS')" >&2; pass; }

"$JABC" "$_CASE/driver.js" "$LIB" >"$WORK/t.out" 2>"$WORK/t.err" || {
    echo "--- stderr ---"; cat "$WORK/t.err"
    _fail "driver exited non-zero"
}

# Expected plain block: one `<verb> <uri>` line per row, in order.
cat > "$WORK/want" <<'EOF'
PLAIN-BEGIN
put be/bro.js
del be/status.js
get be/lib/bro.js
PLAIN-END
COLOR-HAS-SGR yes
COLOR-DIFFERS yes
EOF
cmp -s "$WORK/t.out" "$WORK/want" || {
    echo "--- got ---";  cat -A "$WORK/t.out"
    echo "--- want ---"; cat -A "$WORK/want"
    _fail "table render mismatch"
}
echo "ok   table rows render plain + colour (feedRow)"

pass
