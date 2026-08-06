#!/bin/sh
# test/status/edited-conflict — STATUS-017 (DIS-080 §4): conflict liveness is
# ROW-scoped, not content-scoped.  A `con` path keeps statusing `con` (wt `!`,
# red) through any number of local edits — resolution is the next post/get
# barrier, never a byte pattern.  The old marker-degrade rule (`con` -> `mod`
# once the fences vanish) is overturned: markerless bytes carry no fences at all.
#
#       T0 ── T1          ← cur (trunk): T1 sets line2=Y
#         \
#          F1             ← ?feat: F1 sets line2=X
#
#  `patch '#F1'` clashes on line 2 -> a durable `con f.txt` wtlog row.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/status/edited-conflict
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "status/edited-conflict: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "status/edited-conflict: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
#  Pin the clock so the weave's RGA hash tie-break (and thus the merged bytes)
#  is reproducible run-to-run — a TEST artifact, not a merge bug (patchcase.sh).
: "${SOURCE_DATE_EPOCH:=1467331200}"; export SOURCE_DATE_EPOCH   # 2016-07-01Z
: "${TZ:=UTC}"; export TZ

: "${TMP:=/tmp}"; export TMP
NAME=edited-conflict
WORK="$TMP/$$/status/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [status/$NAME] $*" >&2; exit 1; }
# jab is ASAN — drop the rolling keeper.idx before each op so an earlier commit's
# fork-point object stays visible after a later post (patchcase.sh idiom).
_jab() { rm -f "$WT"/.be/*/*.keeper.idx 2>/dev/null || true; ( cd "$WT" && "$BE" "$@" ); }
# BRO-030: quad default — f.txt's WT (4th quad) char, or empty if no row.
_bucket() { ( cd "$WT" && "$JABC" status --plain 2>/dev/null ) \
    | sed -nE 's/^.*([.xovXV!]{4}) f\.txt$/\1/p' | sed -E 's/^.{3}//' | head -1; }

WT="$WORK/wt"; mkdir -p "$WT/.be"

# T0 on trunk (post-alone auto-adds the wt); save the trunk tip.
printf 'a\nb\nc\n' > "$WT/f.txt"
_jab post 't0' >/dev/null 2>&1 || _fail "could not seed t0"
BOOT=$("$JABC" "$_ROOT/put/tipsha.js" "$WT")
[ -n "$BOOT" ] || _fail "no trunk tip"

# feat = fork at T0, switch, F1 sets line2=X, back to trunk, T1 sets line2=Y.
_jab put '?feat' >/dev/null 2>&1 || _fail "fork feat"
_jab get '?feat' >/dev/null 2>&1 || _fail "switch feat"
printf 'a\nX\nc\n' > "$WT/f.txt"
_jab put f.txt >/dev/null 2>&1 || _fail "stage f1"
_jab post 'f1 line2=X' >/dev/null 2>&1 || _fail "commit f1"
F1=$("$JABC" "$_ROOT/put/tipsha.js" "$WT")
[ -n "$F1" ] || _fail "no feat tip"
_jab get "?#$BOOT" >/dev/null 2>&1 || _fail "switch back to trunk"
printf 'a\nY\nc\n' > "$WT/f.txt"
_jab put f.txt >/dev/null 2>&1 || _fail "stage t1"
_jab post 't1 line2=Y' >/dev/null 2>&1 || _fail "commit t1"

# absorb F1 -> both sides rewrote line 2 -> conflict (PATCHCONFLICT, non-zero).
_rc=0; _jab patch "#$F1" >/dev/null 2>&1 || _rc=$?
[ "$_rc" -ne 0 ] || _fail "conflicting patch exited 0 (spec: PATCHCONFLICT)"
grep -a "$(printf '\tcon\t')" "$WT/.be/wtlog" "$WT/.be" 2>/dev/null | grep -q 'f\.txt' \
    || _fail "no durable 'con f.txt' row in the wtlog"

b=$(_bucket)
[ "$b" = "!" ] || _fail "after the absorb f.txt wt char '$b', expected '!'"
echo "ok: a markerless patch conflict statuses '!'"

# STATUS-017: a local edit on top does NOT resolve — the row still rules.
printf 'a\nZ\nc\n' > "$WT/f.txt"
b=$(_bucket)
[ "$b" = "!" ] || _fail "after a local edit f.txt wt char '$b', expected '!' (con is row-scoped)"
echo "ok: a local edit over a conflict stays '!'"

# even reverting to the base bytes is NOT a resolution (resolution == posted).
printf 'a\nY\nc\n' > "$WT/f.txt"
b=$(_bucket)
[ "$b" = "!" ] || _fail "after reverting to base f.txt wt char '$b', expected '!' (only a post resolves)"
echo "ok: reverting to the base bytes stays '!' until the next post/get"

echo "PASS [status/$NAME]"
