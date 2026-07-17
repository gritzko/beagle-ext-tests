#!/bin/sh
# test/post/agree — DIS-057: `status` (renderer) and `post` (consumer) derive
# from the ONE unified classifier, so they AGREE on the same tree.  Builds a
# mixed change-set — a staged mod, a staged new, a staged delete, and a kept
# (untouched-tracked) file — then asserts the `jab status` buckets and the
# `jab post` per-file rows are CONSISTENT: every dirty path status shows is
# committed by post under the matching verb, and no path is silently dropped.
# JS-ONLY (the agreement is the DIS-057 invariant; assertions are time-normalised).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/agree
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (LAGS jab); alias BE=$JABC so the
# legacy `"$BE"` seeds run jab.
JABC=${JABC:-${JAB:-${BIN:+$BIN/jab}}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/agree: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC"); BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "post/agree: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
_jstatus() { ( cd "$1" && "$JABC" status --plain 2>/dev/null ) \
    | sed -nE 's/^.{8}([.xovXOV!]{4}) (.*)$/\1 \2/p'; }

WT="$WORK/wt"; mkdir -p "$WT/.be"
( cd "$WT"
  printf 'A\n' > a.txt        # will be modded + staged
  printf 'B\n' > b.txt        # will be deleted + staged
  printf 'KEEP\n' > keep.txt  # untouched tracked (kept)
  "$BE" post 'base' >/dev/null 2>&1 ) || _fail "could not seed the baseline"
( cd "$WT"
  sleep 0.02
  printf 'A2\n' > a.txt        # mod
  printf 'NEW\n' > new.txt     # new
  rm b.txt                     # delete
  "$BE" put a.txt new.txt >/dev/null 2>&1
  "$BE" delete b.txt >/dev/null 2>&1 ) || _fail "could not stage the change-set"

# 1. status (the renderer) shows the staged change-set — BRO-030 quad default
#    (wiki/Status.mkd): lex-sorted `<quad4> <path>`, staged UPPERCASE (mod `...V`,
#    del `...X`, new `...O`).
st=$(_jstatus "$WT")
expst='...V a.txt
...X b.txt
...O new.txt'
[ "$st" = "$expst" ] || _fail "status buckets != golden:
golden:
$expst
js:
$st"
echo "ok: status renders the staged change-set (...V mod / ...X del / ...O new)"

# 2. post (the consumer) commits the SAME set: the banner's quad rows must
#    agree with status — BRO-030 quad default (wiki/Status.mkd): a `put` (mod)
#    is `...V`, `new` is `...O`, `del` is `...X`; keep.txt (count-only ok in
#    status) is NOT reported but survives in the tree.
( cd "$WT" && "$JABC" post 'agree' ) >"$WORK/post.out" 2>"$WORK/post.err" \
    || _fail "jab post failed: $(cat "$WORK/post.err")"
ban=$(sed -E 's/^ *[0-9A-Za-z:]+ +//' "$WORK/post.out" 2>/dev/null \
        | grep -E '^\.\.\.[VOX] ' | sort)
expban='...O new.txt
...V a.txt
...X b.txt'
[ "$ban" = "$expban" ] || _fail "post banner != golden (status/post DISAGREE):
golden:
$expban
js:
$ban"
echo "ok: post commits exactly what status showed (...V a / ...O new / ...X b)"

# 3. the agreement is total: after post the wt is clean (every dirty path status
#    showed is now committed; keep.txt rode through untouched).
st2=$(_jstatus "$WT")
[ -z "$st2" ] || _fail "wt not clean after post — status/post disagree (residual):
$st2"
[ -f "$WT/keep.txt" ] && [ -f "$WT/a.txt" ] && [ -f "$WT/new.txt" ] \
    && [ ! -e "$WT/b.txt" ] || _fail "post tree inconsistent with the change-set"
echo "ok: status and post AGREE on the tree (clean after commit, kept file intact)"

echo "PASS [$NAME]"
