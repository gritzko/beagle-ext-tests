#!/bin/sh
# test/bro/cache — BRO-043 through the REAL UI: a live `jab bro` pager on a pty
# re-fires `:status` three times over one worktree, with a file written into the
# wt between #2 and #3.  The pager's JAB_STATS cache line must show a HIT on the
# warm re-fire and a DROP after the write, and frame #3 must show the new file
# while the cached frame #2 does not.
# Registered by the be/test glob as be-js-bro-cache — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/bro/cache
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "bro/cache: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "bro/cache: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

command -v python3 >/dev/null 2>&1 || { echo "bro/cache: SKIP — no python3" >&2; exit 0; }
python3 -c "import pty,select" 2>/dev/null || { echo "bro/cache: SKIP — no pty module" >&2; exit 0; }
# The cache only exists under a live watcher (the JAB-032 fsw wd API).
"$BE" --eval 'let w=fsw.init(); let d=fsw.dir(w,"/tmp"); fsw.close(w); if(!(d>0)) throw "old";' \
    >/dev/null 2>&1 || { echo "bro/cache: SKIP — jab has no fsw wd API (JAB-032)" >&2; exit 0; }

: "${TMP:=/tmp}"; export TMP
WORK="$TMP/$$/work/brocache"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [bro/cache] $*" >&2; exit 1; }

mkdir -p "$WORK/wt/.be" "$WORK/wt/src"
printf 'r\n' > "$WORK/wt/R.txt"
printf 'a\n' > "$WORK/wt/src/a.txt"
( cd "$WORK/wt" && "$BE" post 'wt one' ) >/dev/null 2>&1 || _fail "seed wt"

python3 "$_CASE/brocache.py" "$BE" "$WORK/wt" > "$WORK/pty.log" 2>&1 || {
    cat "$WORK/pty.log" >&2; _fail "pty session"; }
grep -q '^FAIL' "$WORK/pty.log" && { cat "$WORK/pty.log" >&2; _fail "legs"; }
sed -n 's/^   //p' "$WORK/pty.log"
echo "PASS [bro/cache]"
