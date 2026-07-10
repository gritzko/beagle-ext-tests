#!/bin/sh
# URI-011/BE-033 test/uri011/nav-navnone — a scheme-less `//name` nav authority
# that does NOT resolve to a local worktree must ERROR (NAVNONE), never fall
# back to the cwd repo or the wire: scheme-less `//X` is ALWAYS a worktree,
# dotted or not (remotes carry a transport scheme).  RED-first; SUT=loop; JS-ONLY.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/uri011/nav-navnone
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (it LAGS jab); locate jab and
# alias BE=$JABC so legacy `"$BE" post/put` seeds run jab.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "nav-navnone: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "nav-navnone: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "nav-navnone: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/uri011/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export BE JABC BEDIR

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# A cwd worktree (its `.be` shield) so a swallowed authority WOULD resolve here —
# that is exactly what the bug did.  SRC_ROOT = this scratch root: `//NONEXIST-999`
# maps to $SRC_ROOT/NONEXIST-999 (absent) and must NAVNONE, dotted or not.
_wt="$WORK/wt"; mkdir -p "$_wt/.be"
( cd "$_wt"
  printf 'A\n' > a.txt
  "$BE" post 'base' >/dev/null 2>&1 ) || _fail "baseline seed failed"
export SRC_ROOT="$WORK"

# (a) a dotless `//NONEXIST-999` miss must ERROR with NAVNONE (non-zero exit),
#     NOT render the cwd tree's status and exit 0.
if ( cd "$_wt" && "$JABC" status '//NONEXIST-999' ) >"$WORK/none.out" 2>&1; then
    _fail "(a) //NONEXIST-999 exited 0 (swallowed to cwd repo):
$(cat "$WORK/none.out")"
fi
grep -q 'NAVNONE' "$WORK/none.out" \
    || _fail "(a) //NONEXIST-999 did not report NAVNONE:
$(cat "$WORK/none.out")"
echo "ok: //NONEXIST-999 errors with NAVNONE"

# (b) BE-033: a DOTTED `//host.example/x?main` is a worktree miss too — the
#     cached-remote fall-through is dropped, so it must NAVNONE like any typo.
if ( cd "$_wt" && "$JABC" status '//host.example/x?main' ) >"$WORK/dot.out" 2>&1; then
    _fail "(b) dotted //host.example exited 0 (cached-remote fall-through?):
$(cat "$WORK/dot.out")"
fi
grep -q 'NAVNONE' "$WORK/dot.out" \
    || _fail "(b) dotted //host.example did not report NAVNONE:
$(cat "$WORK/dot.out")"
echo "ok: dotted //host.example errors with NAVNONE"

echo "PASS [$NAME]"
