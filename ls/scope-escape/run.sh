#!/bin/sh
# BE-028 test/ls/scope-escape — the `ls` SCOPE must stay INSIDE its worktree.
# classifyDir opened `join(wtRoot, scopePfx)` and readdir'd it, where scopePfx
# came from ls.js via a LEXICAL relDir strip that `..` defeats — so an `ls`
# scope with a `..` (`ls ../outside`, `ls ls:../outside`) climbed OUT of the
# worktree and listed a SIBLING tree's files.  The exact defeated-by-`..`
# lexical-prefix pattern BE-011 removed from `wtdir`, surviving in the ls scope
# path.  A `..` scope that leaves the wt must be REFUSED (NAVESCAPE), never
# readdir'd.  RED-first repro; SUT=loop; JS-ONLY.  Mirrors test/uri011/nav-escape.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/ls/scope-escape
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "scope-escape: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "scope-escape: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/ls/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export BE JABC BEDIR

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# SRC_ROOT layout:  $WORK/root (the scoped worktree)  and  $WORK/outside (a
# SIBLING worktree holding a distinctively-named SECRET file that an `ls` scope
# inside `root` must NEVER reach).  Both are real worktrees (each a `.be`
# shield) so a lexical `..` scope WOULD list `outside`.
_root="$WORK/root"; mkdir -p "$_root/.be"
( cd "$_root"
  printf 'INSIDE\n' > a.txt
  "$BE" post 'root base' >/dev/null 2>&1 ) || _fail "root seed failed"
_out="$WORK/outside"; mkdir -p "$_out/.be"
( cd "$_out"
  printf 'SECRET-OUTSIDE\n' > secret.txt
  "$BE" post 'outside base' >/dev/null 2>&1 ) || _fail "outside seed failed"
export SRC_ROOT="$WORK"

# (0) sanity: a legit `ls:` inside root lists its OWN a.txt (the INSIDE tree).
( cd "$_root" && "$JABC" ls 'ls:' ) >"$WORK/ok.out" 2>&1 \
    || _fail "(0) legit ls: failed:
$(cat "$WORK/ok.out")"
grep -q 'a.txt' "$WORK/ok.out" \
    || _fail "(0) ls: did not list a.txt:
$(cat "$WORK/ok.out")"
echo "ok: ls: lists the scoped worktree's own entries"

# (a) `ls ../outside` — a bare `..` scope — must be REFUSED (NAVESCAPE, non-zero),
#     never readdir the sibling `outside` tree.
if ( cd "$_root" && "$JABC" ls '../outside' ) >"$WORK/esc1.out" 2>&1; then
    _fail "(a) ls ../outside exited 0 (scope escaped the worktree):
$(cat "$WORK/esc1.out")"
fi
grep -q 'secret.txt' "$WORK/esc1.out" \
    && _fail "(a) ls ../outside REACHED the outside tree:
$(cat "$WORK/esc1.out")"
grep -q 'NAVESCAPE' "$WORK/esc1.out" \
    || _fail "(a) ls ../outside did not report NAVESCAPE:
$(cat "$WORK/esc1.out")"
echo "ok: ls ../outside refused with NAVESCAPE"

# (b) `ls ls:../outside` — the scheme-carrying `..` scope — must likewise refuse.
if ( cd "$_root" && "$JABC" ls 'ls:../outside' ) >"$WORK/esc2.out" 2>&1; then
    _fail "(b) ls ls:../outside exited 0 (scope escaped the worktree):
$(cat "$WORK/esc2.out")"
fi
grep -q 'secret.txt' "$WORK/esc2.out" \
    && _fail "(b) ls ls:../outside REACHED the outside tree:
$(cat "$WORK/esc2.out")"
grep -q 'NAVESCAPE' "$WORK/esc2.out" \
    || _fail "(b) ls ls:../outside did not report NAVESCAPE:
$(cat "$WORK/esc2.out")"
echo "ok: ls ls:../outside refused with NAVESCAPE"

echo "PASS [$NAME]"
