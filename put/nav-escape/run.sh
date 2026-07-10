#!/bin/sh
# BE-011 test/put/nav-escape — `be put` must not stage/mutate a file OUTSIDE the
# worktree via a `..` climb.  Honest note: put's plain path arg is ALREADY
# confined — stage.isMeta(raw) (put.js) rejects any `..` segment before the
# lstat/setMtime sites, so `put ../outside/secret.txt` skips as "is a meta path"
# → PUTNONE.  This is a CONFINEMENT GUARD (green pre- and post-fix); the
# BE-011 wtJoin swap at those opens is a defensive twin of the isMeta gate.
# SUT=loop; JS-ONLY.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/put/nav-escape
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "nav-escape: cannot locate jab (set BIN=)" >&2; exit 2; }
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "nav-escape: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/put/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$WORK/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$WORK/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export BE JABC BEDIR
export SRC_ROOT="$WORK"

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# Layout:  $WORK/root  (the worktree)  and  $WORK/outside/secret.txt  (a plain
# file OUTSIDE the wt that `../outside/secret.txt` reaches via a `..` climb).
_root="$WORK/root"; mkdir -p "$_root/.be"
( cd "$_root"
  printf 'INSIDE\n' > a.txt
  "$JABC" post 'root base' >/dev/null 2>&1 ) || _fail "root seed failed"
_out="$WORK/outside"; mkdir -p "$_out"
printf 'SECRET-OUTSIDE\n' > "$_out/secret.txt"
_before=$(stat -c %Y "$_out/secret.txt")

# `put ../outside/secret.txt` must REFUSE (non-zero) and must NOT stage or
# restamp the outside file (its mtime is the setMtime provenance pin put would
# write on a stage; an escape would move it).
if ( cd "$_root" && "$JABC" put ../outside/secret.txt ) >"$WORK/esc.out" 2>&1; then
    _fail "(a) put ../outside/secret.txt exited 0 (staged an out-of-tree path):
$(cat "$WORK/esc.out")"
fi
[ -f "$_out/secret.txt" ] || _fail "(a) put ../outside/secret.txt removed the outside file"
_after=$(stat -c %Y "$_out/secret.txt")
[ "$_before" = "$_after" ] \
    || _fail "(a) put ../outside/secret.txt RESTAMPED the outside file (mtime $_before -> $_after)"
grep -q 'outside/secret.txt' "$WORK/esc.out" && grep -q 'put ' "$WORK/esc.out" \
    && _fail "(a) put staged a row for the out-of-tree path:
$(cat "$WORK/esc.out")"
echo "ok: put ../outside/secret.txt refused, outside file un-staged and un-restamped"

echo "PASS [$NAME]"
