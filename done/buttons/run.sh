#!/bin/sh
# test/done/buttons — BE-040 r3: `[done]` buttons on the `:todo` LIST rows.
# Every OPEN ticket row (board AND topic list) carries the BE-041 house button
# pair AFTER its existing hidden `U` (`todo KEY`) nav: a ` ` sep, a VISIBLE
# 'Y'-tag `[done]` label, then a hidden `O` token whose bytes are the raw spell
# `done <KEY>` (nothing else) — the pager's _uriAt follows the O verbatim, so a
# click closes the ticket while a title click still navigates.  Closed rows
# never list, so they get no button.  `--plain` output stays byte-identical to
# the committed pre-change goldens (buttons are pager-only chrome).  The ticket
# tree is a FIXTURE under $TMP via $TODO_ROOT — never the live journal.
# Registered by the be/test glob as be-js-done-buttons — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/done/buttons
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "done/buttons: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "done/buttons: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=buttons
WORK="$TMP/$$/done/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [done/$NAME] $*" >&2; exit 1; }

# --- the FIXTURE ticket tree (MUST match the committed goldens) ---------------
# FIX-001 thin open, FIX-002 fat open, FIX-003 [DONE] (never lists, no button),
# PUT-001 a second topic so the BOARD carries buttons across topics.
META="$WORK/meta"
mkdir -p "$META/todo/FIX/FIX-002" "$META/todo/PUT"
printf '#   Fixture board\n' > "$META/todo/README.mkd"
printf '#   FIX topic\n' > "$META/todo/FIX/README.mkd"
printf '#   FIX-001 [MED]: thin sample\n' > "$META/todo/FIX/FIX-001.mkd"
printf '#   FIX-002: fat sample\n\nFat body.\n' > "$META/todo/FIX/FIX-002/README.mkd"
printf '#   FIX-003 [DONE]: closed sample\n' > "$META/todo/FIX/FIX-003.mkd"
printf '#   PUT-001: other-topic sample\n' > "$META/todo/PUT/PUT-001.mkd"
export TODO_ROOT="$META"

# --- a minimal seeded worktree to run the loop from --------------------------
WT="$WORK/wt"; mkdir -p "$WT/.be"
cd "$WT"
printf 'seed\n' > a.txt
"$BE" post 'seed commit' >/dev/null 2>&1 || _fail "seed post"

# --- 1. --plain is byte-identical to the PRE-change goldens -------------------
"$BE" todo --plain > "$WORK/board.plain" 2>&1 || _fail "jab todo --plain failed"
cmp -s "$_CASE/board.golden" "$WORK/board.plain" || {
    diff "$_CASE/board.golden" "$WORK/board.plain" >&2 || true
    _fail "board --plain drifted from the pre-change golden (buttons must be pager-only)"
}
"$BE" todo FIX --plain > "$WORK/topic.plain" 2>&1 || _fail "jab todo FIX --plain failed"
cmp -s "$_CASE/topic.golden" "$WORK/topic.plain" || {
    diff "$_CASE/topic.golden" "$WORK/topic.plain" >&2 || true
    _fail "topic --plain drifted from the pre-change golden (buttons must be pager-only)"
}

# --- 2. --tlv: every OPEN list row carries U nav THEN the Y/O button pair ------
"$BE" todo --tlv > "$WORK/board.tlv" 2>/dev/null || _fail "jab todo --tlv failed"
[ -s "$WORK/board.tlv" ] || _fail "todo --tlv emitted ZERO bytes"
"$JABC" "$_CASE/check.js" "$WORK/board.tlv" FIX-001 FIX-002 PUT-001 -- FIX-003 \
    > "$WORK/check1.out" 2>&1 || { cat "$WORK/check1.out" >&2; _fail "board button assertions failed"; }
"$BE" todo FIX --tlv > "$WORK/topic.tlv" 2>/dev/null || _fail "jab todo FIX --tlv failed"
"$JABC" "$_CASE/check.js" "$WORK/topic.tlv" FIX-001 FIX-002 -- FIX-003 PUT-001 \
    > "$WORK/check2.out" 2>&1 || { cat "$WORK/check2.out" >&2; _fail "topic button assertions failed"; }

echo "PASS [done/$NAME]"
