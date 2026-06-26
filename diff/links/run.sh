#!/bin/sh
# test/diff/links — BRO-006: be/views/diff/diff.js emits `U` click-targets so a
# pager left-click on a diff hunk opens the file at the line (the producer half
# of BRO-005 mouse nav, mirroring C graf/GRAF.c:522/535).  A jab unit leg over
# the worktree's views/diff/diff.js (no native `be` / no scratch store needed —
# the test builds its diff hunk straight from the weave bindings).  Picked up by
# the test/CMakeLists `*/*/run.sh` glob as be-js-diff-links (NO CMakeLists edit).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/diff/links
NAME=$(basename "$_CASE")
_BIN="${BIN:-}"
JABC=${JABC:-${JAB:-${_BIN:+$_BIN/jab}}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "links: cannot locate jab (set BIN= or JAB=)" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
: "${TMP:=/tmp}"; export TMP

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# The unit script lives IN the be/ tree, so jab's upward be/-scan resolves its
# be-relative require("views/diff/diff.js") (the test/store.js unit pattern).
# A failed assert THROWS → non-zero exit (the gate); io.log's `OK` marker lands
# on stderr, so check both legs.  ASAN suppression noise also rides stderr.
_out="$TMP/links.$$.log"
_rc=0
"$JABC" "$_CASE/links.js" >"$_out" 2>&1 || _rc=$?
if [ "$_rc" != 0 ]; then
    cat "$_out"; rm -f "$_out"; _fail "links.js exited non-zero ($_rc)"
fi
grep -q 'links.js OK' "$_out" || { cat "$_out"; rm -f "$_out"; _fail "links.js did not report OK"; }
rm -f "$_out"
echo "PASS [$NAME]"
