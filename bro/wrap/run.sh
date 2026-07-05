#!/bin/sh
# test/bro/wrap — BRO-014 the pager soft-wrap / no-wrap toggle.  One headless leg
# over the worktree's views/bro/pager.js + view/bro.js: a wide logical line indexes
# to >1 soft-wrap rows but exactly 1 clamped no-wrap row; `w` flips the current
# view in place; `W` sets a per-type default a new same-type view inherits.
# SKIP-guarded like the sibling pager case (needs the pager handler + tty binding).
. "$(dirname "$0")/../lib/brocase.sh"

PAGER="${PAGER_LIB:-$BROWT/views/bro/pager.js}"
LIB="${LIB:-$BROWT/view/bro.js}"
[ -f "$PAGER" ] || { echo "wrap: SKIP — no views/bro/pager.js at $BROWT" >&2; pass; }
[ -f "$LIB" ]   || { echo "wrap: SKIP — no view/bro.js at $BROWT" >&2; pass; }

# SKIP if the jab build lacks the tty binding — the pager (and this driver) is blocked.
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.raw === "function" &&
           typeof tty.size === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo err)
[ "$HAS" = "yes" ] || { echo "wrap: SKIP — jab has no tty binding (got '$HAS')" >&2; pass; }

"$JABC" "$_CASE/driver.js" "$PAGER" "$LIB" >"$WORK/d.out" 2>"$WORK/d.err" || {
    echo "--- stderr ---"; cat "$WORK/d.err"; _fail "driver exited non-zero"; }
if grep -q '^FAIL' "$WORK/d.out"; then
    echo "--- driver out ---"; cat "$WORK/d.out"; _fail "driver check(s) failed"; fi
grep -q '^DONE' "$WORK/d.out" || { echo "--- driver out ---"; cat "$WORK/d.out"; _fail "driver did not finish"; }
echo "ok   pager wrap toggle (soft/nowrap index + w/W keys)"

pass
