#!/bin/sh
# BE-011 test/uri011/nav-escape — wtdir SRC_ROOT confinement must be PHYSICAL,
# not a lexical prefix compare.  A nav authority/path that resolves OUTSIDE the
# named tree via `..` (`//name/../../outside`, `//../outside`) must be REFUSED
# with a code-worded throw (NAVESCAPE), never adopt the outside tree.  resolve()
# (core/discover.js) normalises the path over SEGMENTS (shared/util/path.js
# resolveInTree) and throws on any climb above the tree root.  RED-first repro;
# SUT=loop; JS-ONLY.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/uri011/nav-escape
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "nav-escape: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "nav-escape: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/uri011/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export BE JABC BEDIR

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# SRC_ROOT layout:  $WORK/root  (the named tree, //root)  and  $WORK/outside
# (a SIBLING tree that MUST be unreachable via `..`).  Both are real worktrees
# (each a `.be` shield) so a lexical-prefix escape WOULD anchor `outside`.
_root="$WORK/root"; mkdir -p "$_root/.be"
( cd "$_root"
  printf 'INSIDE\n' > a.txt
  "$BE" post 'root base' >/dev/null 2>&1 ) || _fail "root seed failed"
_out="$WORK/outside"; mkdir -p "$_out/.be"
( cd "$_out"
  printf 'SECRET-OUTSIDE\n' > secret.txt
  "$BE" post 'outside base' >/dev/null 2>&1 ) || _fail "outside seed failed"
export SRC_ROOT="$WORK"

# (0) sanity: a legit `//root` nav resolves and renders the INSIDE tree.
( cd "$_root" && "$JABC" ls '//root' ) >"$WORK/ok.out" 2>&1 \
    || _fail "(0) legit //root nav failed:
$(cat "$WORK/ok.out")"
grep -q 'a.txt' "$WORK/ok.out" \
    || _fail "(0) //root did not list a.txt:
$(cat "$WORK/ok.out")"
echo "ok: //root resolves to the named tree"

# (a) `//root/../../outside` must be REFUSED (NAVESCAPE, non-zero), never render
#     outside/secret.txt — the JS twin of DOG-009's physical `..` escape.
if ( cd "$_root" && "$JABC" ls '//root/../../outside' ) >"$WORK/esc1.out" 2>&1; then
    _fail "(a) //root/../../outside exited 0 (escaped SRC_ROOT confinement):
$(cat "$WORK/esc1.out")"
fi
grep -q 'secret.txt' "$WORK/esc1.out" \
    && _fail "(a) //root/../../outside REACHED the outside tree:
$(cat "$WORK/esc1.out")"
grep -q 'NAVESCAPE' "$WORK/esc1.out" \
    || _fail "(a) //root/../../outside did not report NAVESCAPE:
$(cat "$WORK/esc1.out")"
echo "ok: //root/../../outside refused with NAVESCAPE"

# (b) `//../outside` (a `..` HOST) must likewise be REFUSED with NAVESCAPE.
if ( cd "$_root" && "$JABC" ls '//../outside' ) >"$WORK/esc2.out" 2>&1; then
    _fail "(b) //../outside exited 0 (escaped via a .. host):
$(cat "$WORK/esc2.out")"
fi
grep -q 'secret.txt' "$WORK/esc2.out" \
    && _fail "(b) //../outside REACHED the outside tree:
$(cat "$WORK/esc2.out")"
grep -q 'NAVESCAPE' "$WORK/esc2.out" \
    || _fail "(b) //../outside did not report NAVESCAPE:
$(cat "$WORK/esc2.out")"
echo "ok: //../outside refused with NAVESCAPE"

echo "PASS [$NAME]"
