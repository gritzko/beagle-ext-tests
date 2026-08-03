#!/bin/sh
# test/status/conflict — STATUS-005: a get-merge that hits a conflict must land
# a durable `con` row in the wtlog (.be) AND be statused `con` (red, the mis/del
# severity), NOT a plain yellow `mod` (indistinguishable from an ordinary edit —
# the 2026-07-10 work/JS-117 incident).
#
#       T0 ── (feat: F1 sets line2=X)      cur switches trunk->feat->trunk
#  wt on trunk T0, dirty edit line2=Y, then `get ?#F1` weave-merges feat in:
#  ours(Y) vs theirs(X) over base(b) diverge on the same anchor.
#
#  PATCH-025/DIS-080: the merge writes the RGA LIVE reading (both sides' tokens
#  in weave order) — NO `<<<<`/`||||`/`>>>>`.  STATUS-017: the `con` row alone
#  keeps it `...!`; a later hand edit no longer degrades it to `...v`.
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
# STATUS-018: the per-column tally line (`N wt, N staged, N con`) — the only
# place a row can spell BOTH the staged fact and the conflict at once.
_summary() { ( cd "$WT" && "$JABC" status --plain 2>/dev/null ) | tail -1; }

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

# PATCH-025: markerless — the merge leaves BOTH sides' tokens, no fences.
if grep -q '<<<<' "$WT/f.txt"; then _fail "conflict fences written by the get-merge"; fi
grep -q 'X' "$WT/f.txt" || _fail "theirs token missing from the merged f.txt"
grep -q 'Y' "$WT/f.txt" || _fail "ours token missing from the merged f.txt"

# a durable `con f.txt` row must be in the wtlog, append-only like `put`.  A
# primary repo's wtlog is `.be/wtlog`; a store-backed secondary wt's is `.be`.
grep -a "$(printf '\tcon\t')" "$WT/.be/wtlog" "$WT/.be" 2>/dev/null | grep -q 'f\.txt' \
    || _fail "no durable 'con f.txt' row in the wtlog"

# status must show the conflict as `con`, NOT `mod`.
b=$(_bucket)
[ "$b" = "!" ] || _fail "status shows f.txt wt char '$b', expected '!' (red conflict)"
echo "ok: markerless get-merge conflict statuses '...!' + durable wtlog row"

# STATUS-017 (DIS-080 §4): liveness is the `con` ROW, not the bytes — a hand
# edit re-stamps out of the get band but does NOT resolve; only a post/get does.
printf 'a\nZ\nc\n' > "$WT/f.txt"
b=$(_bucket)
[ "$b" = "!" ] || _fail "hand-edited f.txt wt char '$b', expected '!' (con is row-scoped)"
echo "ok: a hand edit keeps '...!' (resolution == posted)"

# STATUS-018: the SAME conflict, but the path was STAGED before the merge-get.
# The get RE-STAGES what it conflicts on (`put f.txt` THEN `con f.txt`), so the
# staged-intent arm used to preempt the con test: `...V`, con tally 0 — while
# `post`, reading conflicts() off the same ulog, refused that very path.
# First ack leg 2's conflict (a put LATER than the con row) and post it away.
_jab put f.txt       >/dev/null 2>&1 || _fail "ack the leg-2 conflict"
_jab post 'resolved' >/dev/null 2>&1 || _fail "post the leg-2 resolution"
_jab get "?#$BOOT"   >/dev/null 2>&1 || _fail "back to trunk for the staged leg"
printf 'a\nY\nc\n' > "$WT/f.txt"
_jab put f.txt       >/dev/null 2>&1 || _fail "stage ours before the merge"
_jab get "?#$F1"     >/dev/null 2>&1 || true       # CONFMARK -> non-zero, ignore

b=$(_bucket)
[ "$b" = "!" ] || _fail "staged+conflicted f.txt wt char '$b', expected '!'"
s=$(_summary)
case "$s" in *"con"*) ;; *) _fail "summary '$s' does not tally the conflict";; esac
case "$s" in *"staged"*) ;; *) _fail "summary '$s' lost the staged fact";; esac
echo "ok: a con row outranks staged intent — '...!', tallied con AND staged"

# the two readers of one ulog must agree: post refuses exactly what status paints.
if pout=$(_jab post 'still conflicted' 2>&1); then
    _fail "post accepted the staged+conflicted f.txt"
fi
case "$pout" in *"conflict in tracked file f.txt"*) ;;
    *) _fail "post refused with '$pout', expected the f.txt conflict";; esac
echo "ok: status and post agree on the staged conflict"

echo "PASS [status/$NAME]"
