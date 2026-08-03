#!/bin/sh
# test/todo/sort — TODO-004: the TIME SORT of a flat `todo Key:Value` listing.
# gritzko's rule (2026-08-03): "if dirty, use mtime; otherwise, commit time",
# and dirty tickets sort FIRST — an uncommitted edit is the freshest thing a
# ticket tree holds by construction.  So a flat listing is THREE groups:
#   1. dirty tickets, newest fs mtime first;
#   2. committed tickets, newest INTRODUCING-COMMIT time first (BRO-044's
#      `mtime.idx` lane, read through shared/lastcommit.js — this view never
#      walks history itself);
#   3. rows the lane could not attribute, last and stable (check.js covers that
#      one — a two-commit fixture attributes everything).
# mtime ALONE cannot carry freshness: a checkout restamps every file, so case 3
# below ties every mtime on purpose and the order must SURVIVE it.
# The BOARD is deliberately untouched (`todo`, `todo TOPIC` keep their `Sev:`
# order) — case 6 is that regression guard.
# Fixture, not the live journal (URI-016: be.todoRoot() is <project root>/todo
# and the root is DETECTED by the cwd climb, so the tickets live in the run
# worktree's own todo/).  Registered by the be/test glob as be-js-todo-sort.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/todo/sort
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "todo/sort: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "todo/sort: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=sort
WORK="$TMP/$$/todo/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [todo/$NAME] $*" >&2; exit 1; }
# The KEY column of a --plain listing, in listing order, as one line.
# The KEY column of the rows on stdin, in listing order, as one space-joined
# line (a bare `todo TOPIC` row reads `KEY: title`, a filtered one `KEY [v] …`,
# so the trailing colon comes off).
_keys() { awk 'NF { k=$1; sub(/:$/, "", k); printf "%s%s", (n++ ? " " : ""), k }'; }
_want() { # _want <file> <expected key order> <what>  (line 1 is the banner)
  got=$(sed -n '2,$p' "$1" | _keys)
  [ "$got" = "$2" ] || _fail "$3: got '$got' want '$2'"
}

WT="$WORK/wt"; mkdir -p "$WT/.be" "$WT/todo/AAA"
META="$WT"
cd "$WT"

_tk() { # _tk <KEY> <Sev> <title>  — write one ticket file
  mkdir -p "$META/todo/$(echo "$1" | cut -d- -f1)"
  printf '#   %s: %s\nNow: OPEN\nSev: %s\n' "$1" "$3" "$2" \
      > "$META/todo/$(echo "$1" | cut -d- -f1)/$1.mkd"
}

# --- the fixture: FOUR tickets committed OLDEST-KEY-FIRST -------------------
# AAA-001 lands first, AAA-004 last, one commit per second (a git commit's time
# is second-resolution, so the sleeps are what make the four times distinct).
# Freshest-first is therefore the EXACT REVERSE of the topic+number order the
# view used before this ticket — an accident-proof expectation.
printf 'seed\n' > a.txt
"$BE" post 'seed commit' >/dev/null 2>&1 || _fail "seed post"
for n in 001 002 003 004; do
  _tk "AAA-$n" MED "ticket $n"
  "$BE" put "todo/AAA/AAA-$n.mkd" >/dev/null 2>&1 || _fail "put AAA-$n"
  "$BE" post "commit AAA-$n" >/dev/null 2>&1 || _fail "post AAA-$n"
  [ "$n" = 004 ] || sleep 1
done

# --- 1. FRESHEST FIRST: newest introducing commit leads --------------------
"$BE" todo Now:OPEN --plain > "$WORK/1.out" 2>&1 || _fail "todo Now:OPEN failed"
_want "$WORK/1.out" "AAA-004 AAA-003 AAA-002 AAA-001" "freshest-first order"

# --- 2. the same through a TOPIC + filter line and a second key ------------
"$BE" todo AAA Now:OPEN --plain > "$WORK/2.out" 2>&1 || _fail "todo AAA Now:OPEN failed"
_want "$WORK/2.out" "AAA-004 AAA-003 AAA-002 AAA-001" "topic+filter order"
"$BE" todo Sev:MED --plain > "$WORK/2b.out" 2>&1 || _fail "todo Sev:MED failed"
_want "$WORK/2b.out" "AAA-004 AAA-003 AAA-002 AAA-001" "Sev: filter order"

# --- 3. the FRESH-CLONE case: every mtime identical ------------------------
# A checkout restamps every file to one instant, so in a fresh clone all the
# tickets TIE on mtime and an mtime sort degenerates.  Stamp them all the same
# and the order must be UNCHANGED — that is the whole reason for the lane.
touch -t 202001010000.00 "$META/todo/AAA/AAA-00"*.mkd
"$JABC" "$_CASE/check.js" --mtimes "$META/todo/AAA/AAA-001.mkd" \
    "$META/todo/AAA/AAA-002.mkd" "$META/todo/AAA/AAA-003.mkd" \
    "$META/todo/AAA/AAA-004.mkd" > "$WORK/mtimes.out" 2>&1 \
    || { cat "$WORK/mtimes.out" >&2; _fail "fixture: the four mtimes did not tie"; }
"$BE" todo Now:OPEN --plain > "$WORK/3.out" 2>&1 || _fail "todo Now:OPEN (tied mtimes) failed"
_want "$WORK/3.out" "AAA-004 AAA-003 AAA-002 AAA-001" "tied mtimes still order by commit time"

# --- 4. DIRTY FIRST -------------------------------------------------------
# Edit the OLDEST-committed ticket (AAA-001) — it must jump to the TOP, over
# every committed one.  And touch the NEWEST-committed ticket (AAA-004) to a
# LATER wt mtime WITHOUT changing its bytes: it stays clean, so it must NOT
# outrank the dirty row.  That is "dirty above a committed file touched more
# recently in the working tree", the case a plain mtime sort gets wrong.
printf '\nedited in the worktree\n' >> "$META/todo/AAA/AAA-001.mkd"
touch "$META/todo/AAA/AAA-004.mkd"
"$BE" todo Now:OPEN --plain > "$WORK/4.out" 2>&1 || _fail "todo Now:OPEN (dirty) failed"
_want "$WORK/4.out" "AAA-001 AAA-004 AAA-003 AAA-002" "dirty ticket sorts first"

# --- 5. a ticket with NO COMMITTED BLOB AT ALL ----------------------------
# Never put, never posted: the tip carries nothing at its path, so it is dirty
# for free (no content read) and rides the dirty group by mtime.  Its mtime is
# the newest here, so it leads; re-touching AAA-001 puts that one back on top,
# which is the dirty group ordering by mtime and nothing else.
_tk AAA-005 MED "never committed"
"$BE" todo Now:OPEN --plain > "$WORK/5.out" 2>&1 || _fail "todo Now:OPEN (uncommitted) failed"
_want "$WORK/5.out" "AAA-005 AAA-001 AAA-004 AAA-003 AAA-002" "uncommitted ticket leads"
sleep 1
touch "$META/todo/AAA/AAA-001.mkd"
"$BE" todo Now:OPEN --plain > "$WORK/5b.out" 2>&1 || _fail "todo Now:OPEN (re-touched) failed"
_want "$WORK/5b.out" "AAA-001 AAA-005 AAA-004 AAA-003 AAA-002" "dirty group orders by mtime"

# --- 6. the BOARD is NOT time-sorted --------------------------------------
# TODO-004 Goal 1 aside, the `Sev:` order of the board and of a bare topic
# listing is NOT this ticket's to change: CRIT > HIGH > MED > LOW, then number.
# AAA-002 is the OLDEST-but-one commit and the freshest by nothing at all — it
# must still lead the topic on CRIT alone.
_tk AAA-002 CRIT "ticket 002"
_tk AAA-003 HIGH "ticket 003"
"$BE" todo AAA --plain > "$WORK/6.out" 2>&1 || _fail "todo AAA failed"
_want "$WORK/6.out" "AAA-002 AAA-003 AAA-001 AAA-004 AAA-005" "topic keeps the Sev order"
"$BE" todo --plain > "$WORK/6b.out" 2>&1 || _fail "todo (board) failed"
grep -q '^AAA$' "$WORK/6b.out" || _fail "board lost the AAA topic header"
bgot=$(sed -n '2,$p' "$WORK/6b.out" | grep '^  AAA-' | _keys)
[ "$bgot" = "AAA-002 AAA-003 AAA-001 AAA-004 AAA-005" ] \
  || _fail "board lost the Sev order: got '$bgot'"

# --- 7. the comparator itself (groups, ties, unattributed-last) ------------
"$JABC" "$_CASE/check.js" > "$WORK/check.out" 2>&1 \
    || { cat "$WORK/check.out" >&2; _fail "comparator assertions failed"; }

echo "PASS [todo/$NAME]"
