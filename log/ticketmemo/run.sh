#!/bin/sh
# test/log/ticketmemo — LOG-005: a `log:` drive must cost O(1) `.be` climbs, not
# one per ticket-coded commit row.  shared/ticket.js asks `be.navCwd(<project
# root>)` for EVERY issue key in EVERY commit summary, and navCwd -> treeAt
# re-reads and re-PARSES the whole project `.be` each time (~90% of a 287-row
# `jab log`, profiled 2026-08-06).  The fixture is a project root owning
# todo/TKT/TKT-1.mkd plus a worktree whose 20 commit summaries ALL name TKT-1,
# so every row hits the resolver; drive.js then runs the REAL view in-process at
# two row counts and counts the climbs (work, never wall time).
#   RED  (pre-fix): the 16-row drive pays 12 navCwd/treeAt climbs more than the
#                   4-row one, and dag.commitTs re-parses per call.
#   GREEN: both deltas are ZERO and commitTs parses once per (keeper, sha).
# Registered by the be/test glob as be-js-log-ticketmemo — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/log/ticketmemo
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "log/ticketmemo: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "log/ticketmemo: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
WORK="$TMP/$$/log/ticketmemo"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the jsrc symlink (barewords resolve via jab's upward scan).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [log/ticketmemo] $*" >&2; exit 1; }

# --- the PROJECT ROOT: its `.be/` anchor is what projectRoot() climbs to -----
# URI-016: todoRoot() = <project root>/todo, the ONE ticket tree ticket.js probes.
ROOT="$WORK/proj"
mkdir -p "$ROOT/.be" "$ROOT/todo/TKT" "$ROOT/wt/.be"
printf '#   TKT-1: the ticket every commit summary names\n' > "$ROOT/todo/TKT/TKT-1.mkd"

# 20 commits, EVERY summary carrying the resolvable code (the profiled shape).
cd "$ROOT/wt"
printf 'seed\n' > a.txt
"$BE" post 'TKT-1: commit 0' >/dev/null 2>&1 || _fail "seed post"
i=1
while [ "$i" -lt 20 ]; do
    printf 'rev %s\n' "$i" >> a.txt
    "$BE" post "TKT-1: commit $i" >/dev/null 2>&1 || _fail "post $i"
    i=$((i + 1))
done
[ "$("$BE" log:#16 --plain | grep -c '^[0-9a-f]\{8\} ')" = 16 ] \
    || _fail "fixture: log:#16 does not render 16 rows"

"$BE" "$_CASE/drive.js" "$ROOT" "$TMP/$$/jsrc" > "$WORK/out" 2>"$WORK/err" \
    || { cat "$WORK/out" "$WORK/err" >&2; _fail "driver refused"; }
# io.log writes to fd 2 — the driver's leg report lands in err, not out.
grep -E '^(ok |FAIL |cost: )' "$WORK/err" | sed 's/^/  /' || true
grep -q '^PASS$' "$WORK/err" || { cat "$WORK/out" "$WORK/err" >&2; _fail "legs failed"; }

echo "PASS [log/ticketmemo]"
