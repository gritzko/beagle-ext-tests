#!/bin/sh
# test/js/bro/altscreen — BRO-027 the pager on the xterm ALTERNATE SCREEN
# buffer (smcup/rmcup).  Two legs:
#   alt.js — a REAL Pager.run() session over a tty.openpty() slave: the tty
#            byte-stream starts ESC[?1049h (before hide-cursor/mouse-on), ends
#            ESC[?1049l (after mouse-off/SGR-reset/show-cursor, no final clear),
#            and a throw mid-loop still restores via the finally.
#   piped  — `jab bro --plain` with stdout a FILE (non-tty): the output must
#            carry NO ?1049 bytes (the bracket lives inside the tty-only run()).
# SKIP-guarded like test/bro/pager: needs the pager handler + the tty binding.
. "$(dirname "$0")/../lib/brocase.sh"

PAGER="${PAGER_LIB:-$BROWT/views/bro/pager.js}"
[ -f "$PAGER" ] || { echo "altscreen: SKIP — no views/bro/pager.js at $BROWT" >&2; pass; }

# SKIP if the jab build lacks the tty binding (pre-JS-053) — the pager is blocked.
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.raw === "function" &&
           typeof tty.openpty === "function" && typeof tty.size === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo err)
[ "$HAS" = "yes" ] || { echo "altscreen: SKIP — jab has no tty binding (got '$HAS')" >&2; pass; }

# --- leg 1: the run() session bracket over a real pty ----------------------
"$JABC" "$_CASE/alt.js" "$PAGER" >"$WORK/a.out" 2>"$WORK/a.err" || {
    echo "--- stderr ---"; cat "$WORK/a.err"; _fail "alt exited non-zero"; }
if grep -q '^FAIL' "$WORK/a.out"; then
    echo "--- alt out ---"; cat "$WORK/a.out"; _fail "alt check(s) failed"; fi
grep -q '^DONE' "$WORK/a.out" || { echo "--- alt out ---"; cat "$WORK/a.out"; _fail "alt did not finish"; }
echo "ok   pager run() brackets the session in ?1049h ... ?1049l"

# --- leg 2: piped (non-tty) output carries NO ?1049 bytes -------------------
echo "hello alt" > "$WORK/f.txt"
_prc=0; ( cd "$BROWT" && "$JABC" bro --plain "$WORK/f.txt" ) \
    >"$WORK/piped.out" 2>"$WORK/piped.err" || _prc=$?
[ "$_prc" = 0 ] || { echo "--- piped stderr ---"; cat "$WORK/piped.err"; _fail "piped bro exited non-zero"; }
grep -q "hello alt" "$WORK/piped.out" || _fail "piped bro produced no body"
_ALT=$(printf '\033[?1049')
if grep -qF "$_ALT" "$WORK/piped.out"; then _fail "piped output contains ?1049 bytes"; fi
echo "ok   piped bro output carries no ?1049"

pass
