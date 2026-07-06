#!/bin/sh
# URI-011 test/uri011/put-nav-bind — `put //THERE/sub a.txt` from HERE stages the
# file UNDER the nav context (THERE/sub/a.txt), NOT at THERE's root: a verb binds
# its rest paths under arg 0's context dir when be.authority is set (the composed
# `verb(context_uri,…rest)` call).  SUT=loop (jab main.js); JS-ONLY.  Modelled on
# test/uri011/nav-schemed-scope.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/uri011/put-nav-bind
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (it LAGS jab); locate jab and
# alias BE=$JABC so legacy `"$BE" post/put` seeds run jab.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "put-nav-bind: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "put-nav-bind: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "put-nav-bind: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/uri011/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
M="$BEDIR/main.js"

# SRC_ROOT holds HERE (launch cwd) + THERE (nav target); THERE has a `sub/` dir
# with a file to stage.  A leaked bind would stage `a.txt` at THERE's ROOT.
export SRC_ROOT="$WORK"
mkdir -p "$WORK/HERE/.be" "$WORK/THERE/.be" "$WORK/THERE/sub"
printf 'AWAYMARK\n' > "$WORK/THERE/sub/a.txt"

# From HERE, stage `a.txt` UNDER the //THERE/sub context — must land as sub/a.txt.
( cd "$WORK/HERE" && "$JABC" "$M" put //THERE/sub a.txt ) >"$WORK/put.out" 2>&1 \
    || _fail "put //THERE/sub a.txt failed:
$(cat "$WORK/put.out")"

# THERE's status must show sub/a.txt staged (bound under the context dir).
( cd "$WORK/HERE" && "$JABC" "$M" status //THERE --plain ) >"$WORK/st.out" 2>&1 || true
grep -q 'sub/a.txt' "$WORK/st.out" \
    || _fail "(bind) sub/a.txt not staged under the //THERE/sub context:
$(cat "$WORK/st.out")"
# The rest arg must NOT have leaked to THERE's root as a bare `a.txt`.
grep -qE '(^| )a\.txt' "$WORK/st.out" \
    && _fail "(bind) a.txt leaked to THERE's root (rest not bound under context):
$(cat "$WORK/st.out")"
echo "ok: put //THERE/sub a.txt stages THERE/sub/a.txt (rest bound under context)"

echo "PASS [$NAME]"
