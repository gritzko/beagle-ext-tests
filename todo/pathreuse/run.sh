#!/bin/sh
# test/todo/pathreuse — TODO-001: the board render probes NO path twice.  The
# case COUNTS io.stat/io.lstat/io.open over a planted fixture board: listTopic
# must derive a thin `KEY.<ext>` page straight from the io.readdir entry (zero
# stats; only a fat `KEY/` probes README.<ext>), and the work view's wt rows
# must share ONE boardDir + ONE pageFile per key across [?] and [post].
# Pure JS unit case (no worktree, no store) — check.js plants its own fixture
# under $TMP.  Registered by the be/test glob as be-js-todo-pathreuse.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/todo/pathreuse
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "todo/pathreuse: cannot locate jab (set BIN=)" >&2; exit 2; }
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "todo/pathreuse: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
WORK="$TMP/$$/todo/pathreuse"
rm -rf "$WORK"; mkdir -p "$WORK"
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

TMP="$WORK" "$JABC" "$_CASE/check.js" || { echo "FAIL [todo/pathreuse]" >&2; exit 1; }
echo "PASS [todo/pathreuse]"
