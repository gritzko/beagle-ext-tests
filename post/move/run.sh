#!/bin/sh
# test/post/move — DIS-057: a `be put <src>#<dst>` RENAME shows the `rmv`/`mov`
# move PAIR in `jab status` as TWO plain `<bucket> <path>` rows (`rmv` on the
# source, `mov` on the dest — the Dirty.mkd move pair, NO longer collapsed into
# one `mov src#dst` row) AND commits CONSISTENTLY through the unified classifier
# — `post` unlinks the source and adds the destination, so the committed tree
# has dst (with src's bytes) and no src.  JS-ONLY (the landed extension drops the
# dst add — this is the new DIS-057 behavior), asserted against committed
# goldens, time-normalised.
#
# RED before DIS-057: post drops `add <dst>` (the move dst lands `unk`, not
# committed).  GREEN after: the move pair commits as del src + add dst.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/move
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED (LAGS jab); alias BE=$JABC so the
# legacy `"$BE"` seeds run jab.
JABC=${JABC:-${JAB:-${BIN:+$BIN/jab}}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/move: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC"); BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "post/move: SKIP — no $BEDIR/main.js" >&2; exit 0; }
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
# `jab status` reduced to date-normalised `<bucket> <path>` rows.  The date
# column is either `HH:MM` (recent) or `DDMonYY` (old) — match both, then keep
# only the `<3-letter bucket> <path>` tail (header + `?<branch>` summary drop).
_jstatus() { ( cd "$1" && "$JABC" status --plain 2>/dev/null ) \
    | sed -nE 's/^ *[0-9A-Za-z:]+ +([a-z]{3}) +(.*)$/\1 \2/p'; }

WT="$WORK/wt"; mkdir -p "$WT/.be"
( cd "$WT" && printf 'A\n' > a.txt && printf 'B\n' > b.txt \
    && "$BE" post 'base' >/dev/null 2>&1 ) || _fail "could not seed the baseline"
# Stage the rename b.txt -> m.txt (be put renames on disk + writes one
# `put b.txt#m.txt` row).
( cd "$WT" && sleep 0.02 && "$BE" put 'b.txt#m.txt' >/dev/null 2>&1 ) \
    || _fail "could not stage the move"

# 1. status shows the move PAIR as TWO rows: `rmv b.txt` (source) then
#    `mov m.txt` (dest), in the suite's render order (rmv before mov).
st=$(_jstatus "$WT")
exp='rmv b.txt
mov m.txt'
[ "$st" = "$exp" ] || _fail "status move pair != golden:
golden:
$exp
js:
$st"
echo "ok: a rename shows the 'rmv src' + 'mov dst' pair (two rows)"

# 2. post commits the pair CONSISTENTLY: the banner reports del src + add dst.
( cd "$WT" && "$JABC" post 'rename b to m' ) >"$WORK/post.out" 2>"$WORK/post.err" \
    || _fail "jab post failed: $(cat "$WORK/post.err")"
ban=$(grep -vE 'post post:|post \?' "$WORK/post.out" 2>/dev/null \
        | sed -E 's/^ +//' | grep -E '^(add|mod|del) ')
expban='del b.txt
add m.txt'
[ "$ban" = "$expban" ] || _fail "post banner != golden:
golden:
$expban
js:
$ban"
echo "ok: post reports the move pair (del src + add dst)"

# 3. the committed tree is consistent: m.txt is tracked (carrying b.txt's bytes),
#    b.txt is gone, and the wt re-reads clean (no residual unk/mod).
[ -f "$WT/m.txt" ] || _fail "m.txt missing from the wt after post"
[ ! -e "$WT/b.txt" ] || _fail "b.txt should be gone after the move"
printf 'B\n' > "$WORK/exp.m"; cmp -s "$WORK/exp.m" "$WT/m.txt" \
    || _fail "m.txt does not carry b.txt's bytes"
st2=$(_jstatus "$WT")
[ -z "$st2" ] || _fail "wt not clean after post (residual rows):
$st2"
echo "ok: the move pair committed consistently — tree clean, dst tracked"

echo "PASS [$NAME]"
