#!/bin/sh
# BE-011 test/delete/nav-escape — `be delete` must CONFINE its untrusted CLI
# path arg to the worktree.  A `..` climb (`../outside/secret.txt`) that
# resolves OUTSIDE the wt must be REFUSED (NAVESCAPE), never lstat/unlink the
# out-of-tree file.  RED pre-fix: `delete --force ../outside/secret.txt`
# exited 0 and UNLINKED the outside file (join(repo.wt, raw) resolved `..`
# physically); the fix routes the open through path.wtJoin, which throws
# NAVESCAPE on the climb.  SUT=loop; JS-ONLY.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/delete/nav-escape
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "nav-escape: cannot locate jab (set BIN=)" >&2; exit 2; }
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "nav-escape: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/delete/$NAME"
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
  printf 'INSIDE\n' > b.txt
  "$JABC" post 'root base' >/dev/null 2>&1 ) || _fail "root seed failed"
_out="$WORK/outside"; mkdir -p "$_out"
printf 'SECRET-OUTSIDE\n' > "$_out/secret.txt"

# (0) sanity: a legit in-tree `delete b.txt` still works (exit 0, b.txt gone).
( cd "$_root" && "$JABC" delete b.txt ) >"$WORK/ok.out" 2>&1 \
    || _fail "(0) legit in-tree delete failed:
$(cat "$WORK/ok.out")"
[ -f "$_root/b.txt" ] && _fail "(0) delete b.txt did not remove b.txt"
[ -f "$_out/secret.txt" ] || _fail "(0) sanity delete disturbed the outside file"
echo "ok: in-tree delete works, outside untouched"

# (a) `delete --force ../outside/secret.txt` — the RED case: pre-fix this
#     exited 0 and DELETED secret.txt.  Must now REFUSE (NAVESCAPE, non-zero)
#     and LEAVE the outside file in place.
if ( cd "$_root" && "$JABC" delete --force ../outside/secret.txt ) >"$WORK/esc1.out" 2>&1; then
    _fail "(a) delete --force ../outside/secret.txt exited 0 (escaped the wt):
$(cat "$WORK/esc1.out")"
fi
[ -f "$_out/secret.txt" ] \
    || _fail "(a) delete --force ../outside/secret.txt UNLINKED the outside file:
$(cat "$WORK/esc1.out")"
grep -q 'NAVESCAPE' "$WORK/esc1.out" \
    || _fail "(a) delete --force ../outside/secret.txt did not report NAVESCAPE:
$(cat "$WORK/esc1.out")"
echo "ok: delete --force ../outside/secret.txt refused with NAVESCAPE (outside intact)"

# (b) plain `delete ../outside/secret.txt` must likewise REFUSE with NAVESCAPE
#     (pre-fix it lstat'd outside and refused via the dirty-gate, an accidental
#     bounce; now it is an intentional confinement refusal).
if ( cd "$_root" && "$JABC" delete ../outside/secret.txt ) >"$WORK/esc2.out" 2>&1; then
    _fail "(b) delete ../outside/secret.txt exited 0 (escaped the wt):
$(cat "$WORK/esc2.out")"
fi
[ -f "$_out/secret.txt" ] \
    || _fail "(b) delete ../outside/secret.txt UNLINKED the outside file:
$(cat "$WORK/esc2.out")"
grep -q 'NAVESCAPE' "$WORK/esc2.out" \
    || _fail "(b) delete ../outside/secret.txt did not report NAVESCAPE:
$(cat "$WORK/esc2.out")"
echo "ok: delete ../outside/secret.txt refused with NAVESCAPE (outside intact)"

echo "PASS [$NAME]"
