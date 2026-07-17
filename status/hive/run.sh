#!/bin/sh
# test/status/hive — a `.gitignore` has effect only INSIDE its own repo: the
# ignore chain (shared/util/ignore.js load()) must stop its upward walk at the
# first repo boundary (`.git`/`.be`), not at $HOME.  An ENCLOSING repo ignoring
# the worktrees' parent dir (journal's `work/`, BE-031) must not swallow
# a worktree checked out beneath it — with the bug, every tracked file reads `mis`
# and `be put` dies with PUTNONE (hit live when BE-037 moved worktrees under
# `journal/work/`).  Fixture: outer/.gitignore says `work/`; the worktree is seeded
# at outer/work/WT; status must read the seed clean, put must stage.  The
# worktree's OWN .gitignore must still apply (junk/ stays hidden).  Registered by
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

# --- FIXTURE: an enclosing repo ignoring the work/ dir, a wt beneath it ----
OUTER="$WORK/outer"
WT="$OUTER/work/WT"
mkdir -p "$WT/.be"
printf 'work/\nbuild/\n' > "$OUTER/.gitignore"

cd "$WT"
printf 'seed\n' > a.txt
mkdir junk; printf 'noise\n' > junk/n.txt
printf 'junk/\n' > .gitignore
"$BE" post 'seed commit' >/dev/null 2>&1 || _fail "seed post"

# --- 1. status: the tracked file is clean, NOT removed (`...x`) --------------
# BRO-030: quad default — a swallowed file would read `...x`; a clean tree emits
# NO rows, only the summary frame line.
"$BE" status > "$WORK/st.out" 2>&1 || _fail "jab status failed: $(cat "$WORK/st.out")"
grep -q '\.\.\.x a\.txt' "$WORK/st.out" && _fail "enclosing repo's work/ swallowed the wt: a.txt reads removed"
grep -q '\.\.\.x \.gitignore' "$WORK/st.out" && _fail "wt tree invisible: .gitignore reads removed"
grep -q '^?' "$WORK/st.out" || _fail "status emitted no summary (did not classify): $(cat "$WORK/st.out")"

# --- 2. the wt's OWN .gitignore still applies -------------------------------
grep -q 'junk/n\.txt' "$WORK/st.out" && _fail "wt's own .gitignore lost: junk/n.txt surfaced"

# --- 3. put stages (the live failure was PUTNONE: 'no eligible paths') -------
printf 'seed2\n' > a.txt
"$BE" put a.txt > "$WORK/put.out" 2>&1 || _fail "be put PUTNONE'd: $(cat "$WORK/put.out")"
"$BE" status > "$WORK/st2.out" 2>&1 || _fail "jab status (2) failed"
# BRO-030: a staged edit reads UPPERCASE `...V` (staged) in the quad default.
grep -q '\.\.\.V a\.txt' "$WORK/st2.out" || _fail "staged a.txt not reported `...V`: $(cat "$WORK/st2.out")"

echo "PASS [status/$NAME]"
