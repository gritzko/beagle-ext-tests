#!/bin/sh
# test/status/hive — a `.gitignore` has effect only INSIDE its own repo: the
# ignore chain (shared/util/ignore.js load()) must stop its upward walk at the
# first repo boundary (`.git`/`.be`), not at $HOME.  An ENCLOSING repo ignoring
# the cells' parent dir (the hive: journal's `work/`, BE-031) must not swallow
# a cell checked out beneath it — with the bug, every tracked file reads `mis`
# and `be put` dies with PUTNONE (hit live when BE-037 moved cells under
# `journal/work/`).  Fixture: outer/.gitignore says `work/`; the cell is seeded
# at outer/work/CELL; status must read the seed clean, put must stage.  The
# cell's OWN .gitignore must still apply (junk/ stays hidden).  Registered by
# the be/test glob as be-js-status-hive — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/status/hive
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "status/hive: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "status/hive: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=hive
WORK="$TMP/$$/status/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink (jab resolves the
# extension via its upward be/-scan from the worktree cwd).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [status/$NAME] $*" >&2; exit 1; }

# --- FIXTURE: an enclosing repo ignoring the hive dir, a cell beneath it ----
OUTER="$WORK/outer"
CELL="$OUTER/work/CELL"
mkdir -p "$CELL/.be"
printf 'work/\nbuild/\n' > "$OUTER/.gitignore"

cd "$CELL"
printf 'seed\n' > a.txt
mkdir junk; printf 'noise\n' > junk/n.txt
printf 'junk/\n' > .gitignore
"$BE" post 'seed commit' >/dev/null 2>&1 || _fail "seed post"

# --- 1. status: the tracked file is clean, NOT `mis` -------------------------
"$BE" status > "$WORK/st.out" 2>&1 || _fail "jab status failed: $(cat "$WORK/st.out")"
grep -q 'mis a\.txt' "$WORK/st.out" && _fail "enclosing repo's work/ swallowed the cell: a.txt reads mis"
grep -q 'mis \.gitignore' "$WORK/st.out" && _fail "cell tree invisible: .gitignore reads mis"
grep -q 'ok' "$WORK/st.out" || _fail "status reports no clean files: $(cat "$WORK/st.out")"

# --- 2. the cell's OWN .gitignore still applies -------------------------------
grep -q 'junk/n\.txt' "$WORK/st.out" && _fail "cell's own .gitignore lost: junk/n.txt surfaced"

# --- 3. put stages (the live failure was PUTNONE: 'no eligible paths') -------
printf 'seed2\n' > a.txt
"$BE" put a.txt > "$WORK/put.out" 2>&1 || _fail "be put PUTNONE'd: $(cat "$WORK/put.out")"
"$BE" status > "$WORK/st2.out" 2>&1 || _fail "jab status (2) failed"
grep -q 'put a\.txt' "$WORK/st2.out" || _fail "staged a.txt not reported put: $(cat "$WORK/st2.out")"

echo "PASS [status/$NAME]"
