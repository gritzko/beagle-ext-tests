#!/bin/sh
# test/diff/symlink-leak — JS-069: be/views/diff/diff.js must NOT dereference a
# tracked symlink in its wt-vs-base diff.  A tracked `link -> /etc/passwd` (here:
# an outside file with a secret marker) must diff as the stored link-target
# STRING, never the target file's bytes (treeMap routes kind "l" to `links`, the
# wt side reads via lstat/readlink not io.mmap).  A jab unit over the worktree's
# views/diff/diff.js (no native `be` / no scratch store — the test builds a real
# on-disk symlink and drives the fixed readers directly).  Picked up by the
# test/CMakeLists `*/*/run.sh` glob as be-js-diff-symlink-leak (NO CMakeLists edit).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/diff/symlink-leak
NAME=$(basename "$_CASE")
_BIN="${BIN:-}"
JABC=${JABC:-${JAB:-${_BIN:+$_BIN/jab}}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "symlink-leak: cannot locate jab (set BIN= or JAB=)" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
: "${TMP:=/tmp}"; export TMP

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# The unit script lives IN the be/ tree, so jab's upward be/-scan resolves its
# be-relative require("views/diff/diff.js") (the test/diff/links pattern).
# A failed assert THROWS → non-zero exit (the gate); io.log's `OK` marker lands
# on stderr, so check both legs.  ASAN suppression noise also rides stderr.
_out="$TMP/symlink-leak.$$.log"
_rc=0
"$JABC" "$_CASE/symlink-leak.js" >"$_out" 2>&1 || _rc=$?
if [ "$_rc" != 0 ]; then
    cat "$_out"; rm -f "$_out"; _fail "symlink-leak.js exited non-zero ($_rc)"
fi
grep -q 'symlink-leak.js OK' "$_out" || { cat "$_out"; rm -f "$_out"; _fail "symlink-leak.js did not report OK"; }
rm -f "$_out"
echo "PASS [$NAME]"
