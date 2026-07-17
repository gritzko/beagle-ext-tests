#!/bin/sh
# test/status/conflict — STATUS-005: a get-merge that leaves conflict markers in
# a tracked file must land a durable `con` row in the wtlog (.be) AND be statused
# `con` (red, the mis/del severity), NOT a plain yellow `mod` (indistinguishable
# from an ordinary edit — the 2026-07-10 work/JS-117 incident).  Resolving the
# markers (editing them away) degrades the file to ordinary `mod`.
#
#       T0 ── (feat: F1 sets line2=X)      cur switches trunk->feat->trunk
#  wt on trunk T0, dirty edit line2=Y, then `get ?#F1` weave-merges feat in:
#  ours(Y) vs theirs(X) over base(b) diverge -> `<<<<`/`||||`/`>>>>` in f.txt.
#
#  RED before the fix: `jab status` shows `mod f.txt` (yellow), no con row.
#  GREEN after: `con f.txt` while the markers live; `mod f.txt` once resolved.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/status/conflict
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "status/conflict: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "status/conflict: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
#  Pin the clock so the weave conflict-fence side order (RGA hash tie-break) is
#  reproducible run-to-run (a TEST artifact, not a merge bug) — cf. patchcase.sh.
: "${SOURCE_DATE_EPOCH:=1467331200}"; export SOURCE_DATE_EPOCH   # 2016-07-01Z
: "${TZ:=UTC}"; export TZ

: "${TMP:=/tmp}"; export TMP
NAME=conflict
WORK="$TMP/$$/status/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [status/$NAME] $*" >&2; exit 1; }
# jab is ASAN — drop the rolling keeper.idx before each op so an earlier commit's
# fork-point object stays visible after a later post (patchcase.sh idiom).
_jab() { rm -f "$WT"/.be/*.keeper.idx 2>/dev/null || true; ( cd "$WT" && "$BE" "$@" ); }
# BRO-030: quad default — f.txt's WT (4th quad) char, or empty if no row.
# Conflict spells the wt char `!`, an ordinary edit `v` (track/base/patch same).
_bucket() { ( cd "$WT" && "$JABC" status --plain 2>/dev/null ) \
    | sed -nE 's/^.{8}\.\.\.(.) f\.txt$/\1/p' | head -1; }

WT="$WORK/wt"; mkdir -p "$WT/.be"

# T0 on trunk (post-alone auto-adds the wt); save the trunk tip.
printf 'a\nb\nc\n' > "$WT/f.txt"
_jab post 't0' >/dev/null 2>&1 || _fail "could not seed t0"
# DIS-076: a bare post never mints a ref — read the wt's OWN cur tip instead
# of grepping a refs ULOG that no longer gets a row (RULE ZERO).
BOOT=$("$JABC" "$_ROOT/put/tipsha.js" "$WT")
[ -n "$BOOT" ] || _fail "no trunk tip"

# feat = fork at T0, switch, F1 sets line2=X, back to trunk.
_jab put '?feat' >/dev/null 2>&1 || _fail "fork feat"
_jab get '?feat' >/dev/null 2>&1 || _fail "switch feat"
printf 'a\nX\nc\n' > "$WT/f.txt"
_jab put f.txt >/dev/null 2>&1 || _fail "stage f1"
_jab post 'f1 line2=X' >/dev/null 2>&1 || _fail "commit f1"
# DIS-076: the wt is attached to `feat` right now — its OWN cur tip IS F1.
F1=$("$JABC" "$_ROOT/put/tipsha.js" "$WT")
[ -n "$F1" ] || _fail "no feat tip"
_jab get "?#$BOOT" >/dev/null 2>&1 || _fail "switch back to trunk"

# dirty edit on trunk (line2=Y), then get-merge feat F1 -> weave conflict.
printf 'a\nY\nc\n' > "$WT/f.txt"
_jab get "?#$F1" >/dev/null 2>&1 || true          # CONFMARK -> non-zero exit, ignore

# the merge must have left a real conflict triple in the wt.
grep -q '<<<<' "$WT/f.txt" || _fail "no conflict markers written by the get-merge"

# a durable `con f.txt` row must be in the wtlog, append-only like `put`.  A
# primary repo's wtlog is `.be/wtlog`; a store-backed secondary wt's is `.be`.
grep -a $'\tcon\t' "$WT/.be/wtlog" "$WT/.be" 2>/dev/null | grep -q 'f\.txt' \
    || _fail "no durable 'con f.txt' row in the wtlog"

# status must show the conflict as `con`, NOT `mod`.
b=$(_bucket)
[ "$b" = "!" ] || _fail "status shows f.txt wt char '$b', expected '!' (red conflict)"
echo "ok: get-merge conflict statuses '...!' + durable wtlog row"

# resolve the markers (edit them away) -> degrades to an ordinary edit `...v`.
printf 'a\nZ\nc\n' > "$WT/f.txt"
b=$(_bucket)
[ "$b" = "v" ] || _fail "resolved f.txt wt char '$b', expected 'v' (markers gone)"
echo "ok: resolving the markers degrades '...!' -> '...v'"

echo "PASS [status/$NAME]"
