#!/bin/sh
# test/todo/rows — TODO-005: the `:todo` row grew.  The bare `KEY <title>
# [done]` row now leads with a `Sev:` bullet and carries the wt `[»]` link, the
# ahbeh buttons and the dirty tally in FIXED slots, and `Sub:` families nest on
# dotted rails.  The case pins the row layout (spans + order), the `Sev:` sort,
# the suffix-tolerant wt match, the counts-only-behind-a-wt rule and the
# nesting + cycle rules over a planted fixture board + work/ tree.
# Pure JS unit case (no worktree, no store) — check.js plants its own fixture
# under $TMP.  Registered by the be/test glob as be-js-todo-rows.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/todo/rows
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "todo/rows: cannot locate jab (set BIN=)" >&2; exit 2; }
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "todo/rows: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
WORK="$TMP/$$/todo/rows"
rm -rf "$WORK"; mkdir -p "$WORK"
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

TMP="$WORK" "$JABC" "$_CASE/check.js" || { echo "FAIL [todo/rows]" >&2; exit 1; }
echo "PASS [todo/rows]"
