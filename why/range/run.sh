#!/bin/sh
# WHY-001 test/why/range — `why:<path>?<a>..<b>` colours ONLY (a,b]'s changes,
# INCLUDING deletes (a token removed in the range is surfaced so the delete stays
# visible), while unchanged tokens render plain.  Also covers `why:<path>?<rev>`
# (blame AS OF a rev: scope to that rev's closure — later commits' tokens absent).
#
# Fixture: c1 seeds `alpha/beta/gamma`; c2 rewrites line2 `beta`->`BETA`; c3 adds
# `delta`.  Range c1..c2 must shade EXACTLY the c2 change: the inserted `BETA`
# (inserter in range) and the removed `beta` (remover in range, surfaced); alpha/
# gamma stay plain; `delta` (a c3 token) is out of range → absent.  Rev ?c2 must
# render `alpha/BETA/gamma` with NO `delta`.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/why/range
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (it LAGS jab); locate jab and
# alias BE=$JABC so legacy `"$BE" post/put` seeds run jab.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "why/range: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "why/range: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "why/range: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/why/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# WHY-001: pin commit time (jabc ron.now() rides SOURCE_DATE_EPOCH) for stable shas.
# TEST-003: ADVANCE the epoch PER commit — a FROZEN epoch gives every separate `jab
# post` process the same ron.now(), so all 3 keeper.idx files collide (same name) and
# only the last pack indexes → c1/c2 objects unreadable, `jab log:` shows only 1 sha.
SDE0=1467331200

WT="$WORK/wt"; mkdir -p "$WT/.be"
cd "$WT"
printf 'alpha\nbeta\ngamma\n' > f.txt
SOURCE_DATE_EPOCH=$SDE0 "$BE" post 'c1 seed'          >/dev/null 2>&1 || _fail "post c1"
printf 'alpha\nBETA\ngamma\n' > f.txt
SOURCE_DATE_EPOCH=$((SDE0+60))  "$BE" put f.txt >/dev/null 2>&1
SOURCE_DATE_EPOCH=$((SDE0+60))  "$BE" post 'c2 edit line2' >/dev/null 2>&1 || _fail "post c2"
printf 'alpha\nBETA\ngamma\ndelta\n' > f.txt
SOURCE_DATE_EPOCH=$((SDE0+120)) "$BE" put f.txt >/dev/null 2>&1
SOURCE_DATE_EPOCH=$((SDE0+120)) "$BE" post 'c3 add line4' >/dev/null 2>&1 || _fail "post c3"

# The three short shas, tip-first (log order): c3, c2, c1.
"$BE" log: --plain 2>/dev/null | grep -oaE '^[0-9a-f]{8}' >"$WORK/shas"
C3=$(sed -n '1p' "$WORK/shas"); C2=$(sed -n '2p' "$WORK/shas"); C1=$(sed -n '3p' "$WORK/shas")
[ -n "$C1" ] && [ -n "$C2" ] && [ -n "$C3" ] || _fail "could not read the 3 shas"

# 1. Rev `?<c2>` — blame AS OF c2: alpha/BETA/gamma, NO delta (c3 is out of scope).
( cd "$WT" && "$JABC" why "why:f.txt?$C2" --plain ) >"$WORK/rev" 2>"$WORK/reverr" \
    || _fail "jab why ?<rev> failed ($(cat "$WORK/reverr"))"
grep -q '^BETA$'  "$WORK/rev" || _fail "rev ?c2: 'BETA' missing"
grep -q '^gamma$' "$WORK/rev" || _fail "rev ?c2: 'gamma' missing"
grep -q '^delta$' "$WORK/rev" && _fail "rev ?c2: 'delta' (a c3 line) must be absent"

# 2. Range `?<c1>..<c2>` — colour ONLY the c2 change: the U-targets are ALL c2's
#    (insert BETA + delete beta), NONE from c1/c3.  check.js asserts one distinct
#    origin commit shaded, the removed `beta` surfaced, alpha/gamma plain.
( cd "$WT" && "$JABC" why "why:f.txt?$C1..$C2" --tlv ) >"$WORK/tlv" 2>"$WORK/terr" \
    || _fail "jab why ?a..b --tlv failed ($(cat "$WORK/terr"))"
[ -s "$WORK/tlv" ] || _fail "range --tlv emitted ZERO bytes"
"$JABC" "$_CASE/check.js" "$WORK/tlv" >"$WORK/check.out" 2>&1 \
    || { cat "$WORK/check.out" >&2; _fail "range assertions failed"; }
grep -q "test/why/range OK" "$WORK/check.out" \
    || { cat "$WORK/check.out" >&2; _fail "check.js did not report OK"; }

echo "PASS [$NAME]"
