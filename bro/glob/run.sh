#!/bin/sh
# test/bro/glob — BE-036: the pager word spell expands shell-style globs (`put
# *.c`, `delete src/*`) before dispatch, reusing Tab-completion's wt-confined
# readdir walk.  glob.js drives the Pager internals directly (fd -1, no tty),
# building its own hermetic fixture like test/bro/navescape/navescape.js — so
# there is nothing to build/commit here.  Registered by the be/test glob as
# be-js-bro-glob; SKIPs cleanly when jab / the pager are absent.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/bro/glob
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "bro/glob: cannot locate jab (set BIN=)" >&2; exit 2; }
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/views/bro/pager.js" ] || { echo "bro/glob: SKIP — no pager.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
: "${TMP:=/tmp}"; export TMP

OUT=$("$JABC" "$_CASE/glob.js" 2>&1) || { echo "$OUT" >&2; echo "FAIL [bro/glob]" >&2; exit 1; }
echo "$OUT" | grep -q "PASS be-js-bro-glob" || { echo "$OUT" >&2; echo "FAIL [bro/glob] no PASS line" >&2; exit 1; }
echo "PASS [bro/glob]"
