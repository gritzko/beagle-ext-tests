#!/bin/sh
# test/cat/nav-escape — BE-011: views/cat/cat.js opens the wt file at the
# UNTRUSTED `cat:<path>` URI path.  A `..` climb (`cat:../outside/secret.txt`)
# must be CONFINED to the worktree root — refused (NAVESCAPE), never a silent
# read of a sibling tree OUTSIDE the wt.  The open now composes its path via
# path.wtJoin(repo.wt, path), which throws NAVESCAPE on any climb above the
# root.  RED-first repro (today it reads the outside file); JS-ONLY.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/cat/nav-escape
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "nav-escape: cannot locate jab (set BIN=)" >&2; exit 2; }
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "cat/nav-escape: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/cat/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true                # firewall the JS-tree scan
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true    # jab's be/-scan → the worktree JS
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export JABC BEDIR

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# Layout:  $WORK/root  (the wt, //root)  and a SIBLING $WORK/outside holding a
# distinctive secret.  `cat:../outside/secret.txt` from root escapes the wt via
# one `..` unless the open is worktree-confined.
_root="$WORK/root"; mkdir -p "$_root/.be"
( cd "$_root"
  printf 'INSIDE-CAT\n' > a.txt
  "$JABC" post 'root base' >/dev/null 2>&1 ) || _fail "root seed failed"
_out="$WORK/outside"; mkdir -p "$_out/.be"
( cd "$_out"
  printf 'SECRET-OUTSIDE\n' > secret.txt
  "$JABC" post 'outside base' >/dev/null 2>&1 ) || _fail "outside seed failed"
export SRC_ROOT="$WORK"

# (0) sanity: an in-tree `cat:a.txt` renders the file's own bytes.
( cd "$_root" && "$JABC" cat 'cat:a.txt' ) >"$WORK/ok.out" 2>&1 \
    || _fail "(0) cat:a.txt failed:
$(cat "$WORK/ok.out")"
grep -q 'INSIDE-CAT' "$WORK/ok.out" \
    || _fail "(0) cat:a.txt did not render the file:
$(cat "$WORK/ok.out")"
echo "ok: cat:a.txt renders the in-tree file"

# (a) `cat:../outside/secret.txt` must be REFUSED (NAVESCAPE), never render the
#     outside file — the worktree-open confinement (path.wtJoin).
( cd "$_root" && "$JABC" cat 'cat:../outside/secret.txt' ) >"$WORK/esc.out" 2>&1 || true
grep -q 'SECRET-OUTSIDE' "$WORK/esc.out" \
    && _fail "(a) cat:../outside/secret.txt READ the outside file:
$(cat "$WORK/esc.out")"
grep -q 'NAVESCAPE' "$WORK/esc.out" \
    || _fail "(a) cat:../outside/secret.txt did not report NAVESCAPE:
$(cat "$WORK/esc.out")"
echo "ok: cat:../outside/secret.txt refused with NAVESCAPE"

echo "PASS [$NAME]"
