#!/bin/sh
# test/status/cache — BRO-043: the per-repo VIEW-OUTPUT cache, dropped by the
# watcher.  A resident process (drive.js, the pager's driveSpell shape) runs the
# REAL `status` verb over a REAL forest: top/, its nested repo top/sub/, the
# sibling side/, plus two worktrees (A, B) on ONE store for the `state` axis.
# The assertion is implementation-blind — the CFOLD-001 JAB_STATS object-read
# counter must read ~0 on a cached HIT, and the HIT must render byte-identically
# to a miss.  RED before BRO-043: no cache at all, every re-fire pays full reads.
# Registered by the be/test glob as be-js-status-cache — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/status/cache
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "status/cache: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "status/cache: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

# The cache only exists under a LIVE watcher; a jab without the JAB-032 fsw
# wd API cannot start one, so skip rather than fail (the safety property is
# covered by leg 7 either way).
"$BE" --eval 'let w=fsw.init(); let d=fsw.dir(w,"/tmp"); fsw.close(w); if(!(d>0)) throw "old";' \
    >/dev/null 2>&1 || { echo "status/cache: SKIP — jab has no fsw wd API (JAB-032)" >&2; exit 0; }

: "${TMP:=/tmp}"; export TMP
WORK="$TMP/$$/work/cache"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the jsrc symlink (barewords resolve via jab's upward scan).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [status/cache] $*" >&2; exit 1; }

# --- the forest: top/ (with the nested repo top/sub/) and the sibling side/ ---
mkdir -p "$WORK/top/.be" "$WORK/top/src" "$WORK/top/sub/.be" "$WORK/side/.be"
printf 'r\n'  > "$WORK/top/R.txt"
printf 'a\n'  > "$WORK/top/src/a.txt"
printf 's\n'  > "$WORK/top/sub/S.txt"
printf 'd\n'  > "$WORK/side/D.txt"
( cd "$WORK/top/sub" && "$BE" post 'sub one' ) >/dev/null 2>&1 || _fail "seed sub"
( cd "$WORK/top"     && "$BE" post 'top one' ) >/dev/null 2>&1 || _fail "seed top"
( cd "$WORK/side"    && "$BE" post 'side one' ) >/dev/null 2>&1 || _fail "seed side"

# --- the STORE axis: two worktrees on ONE store (leg 7) ---------------------
# proj/ owns the store; A/ and B/ are store-backed clones both TRACKING its
# `?trunk`.  A commits locally (trunk unmoved), and the driver later PUSHES
# that commit from A — which rewrites the shared `<shard>/refs` tip B's track
# column reads while touching NO file under B.  Only `state` can see it.
mkdir -p "$WORK/proj/.be" "$WORK/A" "$WORK/B"
printf 'one\n' > "$WORK/proj/O.txt"
( cd "$WORK/proj" && "$BE" post 'c0' && "$BE" put '?trunk' ) >/dev/null 2>&1 \
    || _fail "seed proj + ?trunk"
_projclone() { rm -f "$WORK"/proj/.be/*.keeper.idx 2>/dev/null || true
               ( cd "$1" && "$BE" get "file://$WORK/proj/.be?trunk" ); }
_projclone "$WORK/A" >/dev/null 2>&1 || _fail "clone A"
_projclone "$WORK/B" >/dev/null 2>&1 || _fail "clone B"
printf 'two\n' > "$WORK/A/M.txt"
( cd "$WORK/A" && "$BE" put M.txt && "$BE" post 'a1' ) >/dev/null 2>&1 \
    || _fail "A local commit"

# JAB_STATS=1 turns on the CFOLD-001 object-read counters the driver reads.
_drive() {
    JAB_STATS=1 "$BE" "$_CASE/drive.js" "$WORK" "$TMP/$$/jsrc" "$BE" "$1" \
        > "$WORK/out.$1" 2>"$WORK/err.$1" || {
        cat "$WORK/out.$1" "$WORK/err.$1" >&2; _fail "driver ($1) refused"; }
    # io.log writes to fd 2 — the driver's leg report lands in err, not out.
    grep -q '^PASS$' "$WORK/err.$1" || {
        cat "$WORK/out.$1" "$WORK/err.$1" >&2; _fail "legs failed ($1)"; }
    grep -E '^(ok |FAIL |cache: |PASS)' "$WORK/err.$1" | sed 's/^/  /' || true
}
_drive main
# The store axis needs a FRESH process: a `?branch` track resolve is poisoned
# for every later repo once another repo's status ran in the same one.
_drive store
echo "PASS [status/cache]"
