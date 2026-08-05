#!/bin/sh
# test/bro/resize — BRO-045: a terminal RESIZE repaints the pager without a
# keystroke.  render() already re-reads tty.size and rows(cols) re-wraps per
# width, but nothing woke the 100ms key spin, so the screen stayed stale (and,
# on the BRO-027 alt screen, scrambled) until the reader pressed something.
#   resize.js — a REAL Pager.run() session over a tty.openpty() slave: a render
#               hook calls tty.setSize AND SENDS NO KEY; the next frame must
#               carry the new width (cols leg) and the new height (rows-only
#               leg), with the scroll position preserved.
# Only the LAST frame sends "q", so before the fix the session HANGS in the
# spin — the run is bounded by `timeout` and a timeout IS the RED failure.
# SKIP-guarded like the other bro cases: needs the pager handler + tty binding.
# Registered by the be/test glob as be-js-bro-resize.
. "$(dirname "$0")/../lib/brocase.sh"

PAGER="${PAGER_LIB:-$BROWT/views/bro/pager.js}"
[ -f "$PAGER" ] || { echo "resize: SKIP — no views/bro/pager.js at $BROWT" >&2; pass; }

# SKIP if the jab build lacks the tty binding (pre-JS-053) — the pager is blocked.
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.raw === "function" &&
           typeof tty.openpty === "function" && typeof tty.size === "function" &&
           typeof tty.setSize === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo err)
[ "$HAS" = "yes" ] || { echo "resize: SKIP — jab has no tty binding (got '$HAS')" >&2; pass; }

# --- the resize session ----------------------------------------------------
# A stale pager never repaints and never sees the quit key: bound the run so the
# RED case FAILS instead of wedging.  `timeout` is optional (ctest bounds the
# case anyway); without it a pre-fix pager hangs until the harness kills it.
TO=$(command -v timeout || true)
_rc=0
if [ -n "$TO" ]; then
    "$TO" 6 "$JABC" "$_CASE/resize.js" "$PAGER" >"$WORK/r.out" 2>"$WORK/r.err" || _rc=$?
else
    "$JABC" "$_CASE/resize.js" "$PAGER" >"$WORK/r.out" 2>"$WORK/r.err" || _rc=$?
fi
[ "$_rc" = 0 ] || {
    echo "--- resize out ---"; cat "$WORK/r.out"
    echo "--- stderr ---"; cat "$WORK/r.err"
    case $_rc in 124|137|143) _fail "resize session TIMED OUT — the key spin never woke on the resize (exit $_rc)" ;; esac
    _fail "resize exited non-zero ($_rc)"; }
if grep -q '^FAIL' "$WORK/r.out"; then
    echo "--- resize out ---"; cat "$WORK/r.out"; _fail "resize check(s) failed"; fi
grep -q '^DONE' "$WORK/r.out" || { echo "--- resize out ---"; cat "$WORK/r.out"; _fail "resize did not finish"; }
echo "ok   pager repaints on a resize with no keystroke (both axes, scroll kept)"

pass
