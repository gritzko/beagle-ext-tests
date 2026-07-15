#!/bin/sh
# BE-037 test/uri011/nav-empty-host-top — the EMPTY `//` nav authority names the
# TOP tree (what navCwd composes post BE-031), path honoured: from inside a
# nested sub wt, `///sub/dir/f` resolves `<top>/sub/dir/f` (never `<sub>/sub/…`),
# and an empty-host wtdir MISS (repo-less cwd) errors NAVNONE — no silent
# verbatim pass-through to the verb.  RED-first; SUT=loop; JS-ONLY.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/uri011/nav-empty-host-top
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (it LAGS jab); locate jab and
# alias BE=$JABC so legacy `"$BE" post/put` seeds run jab.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "nav-empty-host-top: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "nav-empty-host-top: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "nav-empty-host-top: no jab at $JABC" >&2; exit 2; }
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

# A mini-project: `<root>/work/proj` is the TOP worktree (topWt's `work/` boundary),
# `proj/sub` a nested wt inside it.  SRC_ROOT stays UNSET so the BE-031 layout
# inference (srcRoot = the wt's `work/` parent) is what resolves `//`.
unset SRC_ROOT || true
_top="$WORK/work/proj"; mkdir -p "$_top/.be"
( cd "$_top"
  printf 'TOPFILE\n' > top.txt
  "$BE" post 'base' >/dev/null 2>&1 ) || _fail "top-wt seed failed"
_sub="$_top/sub"; mkdir -p "$_sub/.be"
( cd "$_sub"
  mkdir -p dir
  printf 'IN-TOP-SUB-DIR\n' > dir/f.txt
  "$BE" post 'subbase' >/dev/null 2>&1 ) || _fail "sub-wt seed failed"

# (a) from INSIDE the sub, `///sub/dir/f.txt` must reach `<top>/sub/dir/f.txt`
#     (the pager-composed empty-authority URI) — pre-fix the empty host meant
#     the LAUNCH tree (the sub itself) and the path resolved `<sub>/sub/…` (absent).
( cd "$_sub" && "$JABC" cat '///sub/dir/f.txt' --plain ) >"$WORK/cat.out" 2>&1 \
    || _fail "(a) cat ///sub/dir/f.txt failed:
$(cat "$WORK/cat.out")"
grep -q 'IN-TOP-SUB-DIR' "$WORK/cat.out" \
    || _fail "(a) ///sub/dir/f.txt did not read <top>/sub/dir/f.txt:
$(cat "$WORK/cat.out")"
echo "ok: ///sub/dir/f.txt reaches <top>/sub/dir/f.txt from inside the sub"

# (b) the bare `//` launch form keeps working and = the TOP tree.
( cd "$_sub" && "$JABC" ls '//' --plain ) >"$WORK/ls.out" 2>&1 \
    || _fail "(b) bare ls // failed:
$(cat "$WORK/ls.out")"
grep -q 'top\.txt' "$WORK/ls.out" \
    || _fail "(b) bare // did not list the TOP tree:
$(cat "$WORK/ls.out")"
echo "ok: bare // = the top tree"

# (c) an empty-host wtdir MISS (repo-less cwd) is LOUD: NAVNONE + non-zero,
#     never the raw `///path` passed to the verb verbatim.
_nr="$(rs_norepo_base)/wt"; rm -rf "$_nr"; mkdir -p "$_nr"
ln -sfn "$BEDIR" "$_nr/jsrc" 2>/dev/null || true
if ( cd "$_nr" && "$JABC" status '///no/such/tree' ) >"$WORK/none.out" 2>&1; then
    _fail "(c) repo-less ///no/such/tree exited 0 (silent fall-through):
$(cat "$WORK/none.out")"
fi
grep -q 'NAVNONE' "$WORK/none.out" \
    || _fail "(c) repo-less empty-host miss did not report NAVNONE:
$(cat "$WORK/none.out")"
echo "ok: repo-less empty-host miss errors with NAVNONE"

echo "PASS [$NAME]"
