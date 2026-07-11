#!/bin/sh
# test/sub/nestedput — SUBS-051: `jab put <a>/<b>/<file>` where BOTH <a> and
# <a>/<b> are mounted subs must stage <file> in the INNERMOST sub's own wtlog.
# Before the fix, put's sub-crossing delegation descended only ONE mount:
# stageInSub resolved the shallowest mount and handed the remainder straight to
# the stage engine WITHOUT re-checking it for a nested mount, so a path >=2
# mounts down classified as "exists but is not stageable" in the mid sub and the
# run died `PUTNONE: no eligible paths`.  The fix (put.js stageInSub) descends
# mount by mount, re-probing subMountPrefix against each descended sub and
# accumulating the top-relative display prefix.
#
# JAB-only / keeper-free: the nested mounts are green-field `jab get` clones into
# subdirs of the parent wt (each plants a `.be` FILE redirect — recurse.isMount
# accepts it), no `.gitmodules`, no wire.  Asserts:
#   1. NESTED `put mid/inn/INN.c` from the parent root stages INN.c in the
#      GRANDCHILD (inn) wtlog; banner prints the full `mid/inn/INN.c`; the parent
#      and mid wtlogs record NO put row (the gitlink bump stays POST's job).
#   2. ONE-LEVEL `put mid/MID.c` still stages in the mid wtlog (single-level
#      delegation unchanged).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/sub/nestedput
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "nestedput: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "nestedput: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/sub/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the jsrc shard symlink (jab's upward jsrc-scan resolves
# the JS verbs from the worktree under test, above the /tmp fixtures).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export BE JABC BEDIR

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# --- fixture: a 3-level nested-mount tree, all jab-only green-field clones -----
# storeM / storeI : source stores (project-less colocated primaries) for the mid
#                   and inner subs; P : the parent worktree.  Cloning storeM into
#                   P/mid and storeI into P/mid/inn plants a `.be` FILE redirect
#                   at each level — a live mount for recurse.isMount.
mkdir -p "$WORK/storeM/.be"
( cd "$WORK/storeM" && printf 'mid payload v1\n' > MID.c && "$BE" post 'mid initial' ) \
    >/dev/null 2>&1 || _fail "storeM setup"
mkdir -p "$WORK/storeI/.be"
( cd "$WORK/storeI" && printf 'inn payload v1\n' > INN.c && "$BE" post 'inn initial' ) \
    >/dev/null 2>&1 || _fail "storeI setup"
mkdir -p "$WORK/P/.be"
( cd "$WORK/P" && printf 'top payload v1\n' > TOP.c && "$BE" post 'parent initial' ) \
    >/dev/null 2>&1 || _fail "P setup"

# Mount mid inside P, then inn inside P/mid (double-slash file:// — the single
# slash form has a known path-eating bug).
mkdir -p "$WORK/P/mid"
( cd "$WORK/P/mid" && "$BE" get "file://$WORK/storeM/.be" ) >"$WORK/getmid.out" 2>&1 \
    || { cat "$WORK/getmid.out"; _fail "mount mid"; }
[ -f "$WORK/P/mid/.be" ] || _fail "P/mid/.be not a FILE redirect (mid not mounted)"
[ -f "$WORK/P/mid/MID.c" ] || _fail "P/mid/MID.c not checked out"
mkdir -p "$WORK/P/mid/inn"
( cd "$WORK/P/mid/inn" && "$BE" get "file://$WORK/storeI/.be" ) >"$WORK/getinn.out" 2>&1 \
    || { cat "$WORK/getinn.out"; _fail "mount inn"; }
[ -f "$WORK/P/mid/inn/.be" ] || _fail "P/mid/inn/.be not a FILE redirect (inn not mounted)"
[ -f "$WORK/P/mid/inn/INN.c" ] || _fail "P/mid/inn/INN.c not checked out"

# ============================================================================
# 1. NESTED put: dirty the grandchild file, `put mid/inn/INN.c` from P root.
# ============================================================================
printf 'inn payload v2 EDITED\n' > "$WORK/P/mid/inn/INN.c"
_rc=0
( cd "$WORK/P" && "$BE" put mid/inn/INN.c ) >"$WORK/put_nested.out" 2>"$WORK/put_nested.err" || _rc=$?
[ "$_rc" = 0 ] || { echo "--- out ---"; cat "$WORK/put_nested.out"; \
    echo "--- err ---"; cat "$WORK/put_nested.err"; \
    _fail "nested put mid/inn/INN.c FAILED (SUBS-051 bug: PUTNONE, single-level descent)"; }

# The banner row shows the FULL top-relative path at depth 2.
grep -qE 'put[[:space:]]+mid/inn/INN\.c' "$WORK/put_nested.out" \
    || { echo "--- out ---"; cat "$WORK/put_nested.out"; \
         _fail "nested put banner did not print the full 'mid/inn/INN.c' path"; }
# The put row lands in the GRANDCHILD (inn) wtlog only.
grep -qE 'put[[:space:]]+INN\.c' "$WORK/P/mid/inn/.be" \
    || { echo "--- inn/.be ---"; cat "$WORK/P/mid/inn/.be"; \
         _fail "nested put did NOT stage INN.c in the grandchild (inn) wtlog"; }
# Neither the parent nor the mid wtlog records a put row (gitlink bump is POST's).
grep -qE '[[:space:]]put[[:space:]]' "$WORK/P/.be/wtlog" \
    && { echo "--- P/.be/wtlog ---"; cat "$WORK/P/.be/wtlog"; \
         _fail "parent wtlog gained a put row (should be POST's job)"; }
grep -qE '[[:space:]]put[[:space:]]' "$WORK/P/mid/.be" \
    && { echo "--- P/mid/.be ---"; cat "$WORK/P/mid/.be"; \
         _fail "mid wtlog gained a put row (staging must land in the innermost sub)"; }
echo "ok   1. nested put mid/inn/INN.c stages in the grandchild wtlog only (full path banner)"

# SUBS-051 note: a SECOND `put mid/inn/INN.c` re-stages (appends another put
# row) rather than skipping "is unchanged".  This is PRE-EXISTING jab-wide
# behaviour (a plain single-repo re-put of a staged-but-uncommitted dirty file
# re-stages too — the "is unchanged" fast-path only covers files matching the
# COMMITTED baseline), NOT specific to nested subs, so it is only noted here.

# ============================================================================
# 2. ONE-LEVEL control: dirty a mid file, `put mid/MID.c` from P root — the
#    single-level delegation must still stage it in the mid wtlog.
# ============================================================================
printf 'mid payload v2 EDITED\n' > "$WORK/P/mid/MID.c"
_rc=0
( cd "$WORK/P" && "$BE" put mid/MID.c ) >"$WORK/put_one.out" 2>"$WORK/put_one.err" || _rc=$?
[ "$_rc" = 0 ] || { echo "--- out ---"; cat "$WORK/put_one.out"; \
    echo "--- err ---"; cat "$WORK/put_one.err"; _fail "one-level put mid/MID.c FAILED"; }
grep -qE 'put[[:space:]]+mid/MID\.c' "$WORK/put_one.out" \
    || { cat "$WORK/put_one.out"; _fail "one-level put banner did not print 'mid/MID.c'"; }
grep -qE 'put[[:space:]]+MID\.c' "$WORK/P/mid/.be" \
    || { echo "--- P/mid/.be ---"; cat "$WORK/P/mid/.be"; \
         _fail "one-level put did NOT stage MID.c in the mid wtlog"; }
echo "ok   2. one-level put mid/MID.c stages in the mid wtlog (single-level delegation intact)"

echo "PASS [$NAME]"
