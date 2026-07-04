#!/bin/sh
# URI-011 test/uri011/nav-navnone — a scheme-less `//name` nav authority that
# does NOT resolve to a local tree under SRC_ROOT must ERROR (NAVNONE), not
# silently fall back to the cwd repo.  authorityRepo (core/loop.js) distinguishes
# a mistyped LOCAL tree (dotless host → NAVNONE) from a CACHED REMOTE (dotted
# `//host…` → left to the wire, no throw).  RED-first repro; SUT=loop; JS-ONLY.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/uri011/nav-navnone
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "nav-navnone: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-${JAB:-$_BIN/jab}}
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
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
export BE JABC BEDIR

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# A cwd worktree (its `.be` shield) so a swallowed authority WOULD resolve here —
# that is exactly what the bug did.  SRC_ROOT = this scratch root: `//NONEXIST-999`
# maps to $SRC_ROOT/NONEXIST-999 (absent) and `//host.dotted` likewise absent, but
# only the DOTLESS name must NAVNONE.
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

# (b) a DOTTED `//host.example/x?main` cached remote must NOT NAVNONE (it is left
#     to the wire — a dotted host is a real host, never a local typo).
( cd "$_wt" && "$JABC" status '//host.example/x?main' ) >"$WORK/dot.out" 2>&1 || true
grep -q 'NAVNONE' "$WORK/dot.out" \
    && _fail "(b) a dotted //host.example NAVNONE'd (must be left to the wire):
$(cat "$WORK/dot.out")"
echo "ok: dotted //host.example does not NAVNONE"

echo "PASS [$NAME]"
