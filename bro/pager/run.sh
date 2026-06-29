#!/bin/sh
# test/js/bro/pager — JAB-028 the bro interactive pager.  Two headless legs over
# the worktree's view/bro/pager.js + view/bro.js (no real terminal needed):
#   driver.js — the pure pieces: tlv->hunks reparse, indexAll soft-wrap,
#               paintRow plain+colour, statusURI/statusPos, and the Pager state
#               machine driven by synthetic keys (j/k/space/g/G/: + Enter).
#   pty.js    — the INTERACTIVE cycle over a tty.openpty() slave: raw mode,
#               render-to-a-real-tty, a key read back, and `:`+spell+Enter swap.
# SKIP-guarded like the other bro cases: needs the pager handler in $BROWT.
. "$(dirname "$0")/../lib/brocase.sh"

PAGER="${PAGER_LIB:-$BROWT/views/bro/pager.js}"
LIB="${LIB:-$BROWT/view/bro.js}"
[ -f "$PAGER" ] || { echo "pager: SKIP — no views/bro/pager.js at $BROWT" >&2; pass; }
[ -f "$LIB" ]   || { echo "pager: SKIP — no view/bro.js at $BROWT" >&2; pass; }

# SKIP if the jab build lacks the tty binding (pre-JS-053) — the pager is blocked.
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.raw === "function" &&
           typeof tty.openpty === "function" && typeof tty.size === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo err)
[ "$HAS" = "yes" ] || { echo "pager: SKIP — jab has no tty binding (got '$HAS')" >&2; pass; }

# --- leg 1: the headless pieces -------------------------------------------
"$JABC" "$_CASE/driver.js" "$PAGER" "$LIB" >"$WORK/d.out" 2>"$WORK/d.err" || {
    echo "--- stderr ---"; cat "$WORK/d.err"; _fail "driver exited non-zero"; }
if grep -q '^FAIL' "$WORK/d.out"; then
    echo "--- driver out ---"; cat "$WORK/d.out"; _fail "driver check(s) failed"; fi
grep -q '^DONE' "$WORK/d.out" || { echo "--- driver out ---"; cat "$WORK/d.out"; _fail "driver did not finish"; }
echo "ok   pager headless pieces (tlv/index/paint/status/keys)"

# --- leg 2: the interactive pty smoke test --------------------------------
"$JABC" "$_CASE/pty.js" "$PAGER" >"$WORK/p.out" 2>"$WORK/p.err" || {
    echo "--- stderr ---"; cat "$WORK/p.err"; _fail "pty exited non-zero"; }
if grep -q '^FAIL' "$WORK/p.out"; then
    echo "--- pty out ---"; cat "$WORK/p.out"; _fail "pty check(s) failed"; fi
grep -q '^DONE' "$WORK/p.out" || { echo "--- pty out ---"; cat "$WORK/p.out"; _fail "pty did not finish"; }
echo "ok   pager interactive cycle (raw mode + key + address bar)"

# --- leg 3: BRO-010 status verb-token colour parity -----------------------
# The pager's paintRow must paint the status verb cell (mod/unk/adv/del/cnf)
# with the SAME VERB_SLOT/THEME SGR the DIRECT path (renderHunkLog → C THEME
# .color() sink) emits — i.e. matching `be` / `jab status --color | cat`.
# Compares the pager renderer's bytes against renderHunkLog's for the same hunk.
THEMELIB="${THEMELIB:-$BROWT/view/theme.js}"
[ -f "$THEMELIB" ] || { echo "pager: SKIP verbcolor — no view/theme.js at $BROWT" >&2; pass; }
"$JABC" "$_CASE/verbcolor.js" "$PAGER" "$LIB" "$THEMELIB" >"$WORK/v.out" 2>"$WORK/v.err" || {
    echo "--- stderr ---"; cat "$WORK/v.err"; _fail "verbcolor exited non-zero"; }
if grep -q '^FAIL' "$WORK/v.out"; then
    echo "--- verbcolor out ---"; cat "$WORK/v.out"; _fail "verbcolor check(s) failed"; fi
grep -q '^DONE' "$WORK/v.out" || { echo "--- verbcolor out ---"; cat "$WORK/v.out"; _fail "verbcolor did not finish"; }
echo "ok   pager status verb-token colour matches the direct path (BRO-010)"

pass
