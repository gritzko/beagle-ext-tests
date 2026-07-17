#!/bin/sh
# BRO-029 test/cat/rev — `cat <path>?<rev>` must read the blob AT THAT REV, like
# why: does, even when the path is ABSENT from the checkout.  The bug: cat's
# ?ref read resolved the rev tip-only (core/resolve.js::resolveHex) and hand-
# walked the tree, so a HISTORIC commit missed → SILENT-EMPTY (exit 0, no bytes)
# — the worst mode (scripts read an empty file).  Fix routes ?ref through THE
# resolver (core/resolve_hash.js, URI-016), the same one blob:/why honour:
# resolveHexAny finds any commit; descendPath errs LOUD on an absent path.
#
# Fixture: c1 seeds a.txt; c2 ADDS gone.c; c3 bumps a.txt (so c2 is HISTORIC,
# not the tip).  gone.c is then removed from the checkout.  Asserts:
#   (a) cat gone.c?c2 (and --plain, and the cat: scheme form) emits gone.c's
#       bytes though it is absent from the wt AND from the tip tree;
#   (b) cat nope.c?c2 (a path absent AT THAT REV) fails LOUD (nonzero + CATNOFILE),
#       never silent-empty;
#   (c) plain-wt `cat a.txt` is unchanged.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/cat/rev
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only; alias BE=$JABC so legacy `"$BE" post/put` seeds run jab.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "cat/rev: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "cat/rev: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "cat/rev: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/cat/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# Pin+ADVANCE the epoch PER commit (jab ron.now() rides SOURCE_DATE_EPOCH) for
# stable shas and distinct keeper.idx names (why/range's note).
SDE0=1467331200

WT="$WORK/wt"; mkdir -p "$WT/.be"
cd "$WT"
printf 'INSIDE-A\n' > a.txt
SOURCE_DATE_EPOCH=$SDE0 "$BE" post 'c1 base' >/dev/null 2>&1 || _fail "post c1"
printf 'int main(){return 0;} /* GONE-MARKER */\n' > gone.c
SOURCE_DATE_EPOCH=$((SDE0+60)) "$BE" put gone.c >/dev/null 2>&1 || _fail "put gone.c"
SOURCE_DATE_EPOCH=$((SDE0+60)) "$BE" post 'c2 add gone.c' >/dev/null 2>&1 || _fail "post c2"
printf 'INSIDE-A\nMORE\n' > a.txt
SOURCE_DATE_EPOCH=$((SDE0+120)) "$BE" put a.txt >/dev/null 2>&1 || _fail "put a.txt"
SOURCE_DATE_EPOCH=$((SDE0+120)) "$BE" post 'c3 bump a.txt' >/dev/null 2>&1 || _fail "post c3"

# Short shas, tip-first (log order): c3, c2, c1.
"$BE" log: --plain 2>/dev/null | grep -oaE '^[0-9a-f]{8}' >"$WORK/shas"
C3=$(sed -n '1p' "$WORK/shas"); C2=$(sed -n '2p' "$WORK/shas"); C1=$(sed -n '3p' "$WORK/shas")
[ -n "$C1" ] && [ -n "$C2" ] && [ -n "$C3" ] || _fail "could not read the 3 shas"

# gone.c is HISTORIC (added in c2, gone by c3) — remove it from the checkout too.
rm -f gone.c
[ -e gone.c ] && _fail "gone.c still in checkout"

# (a) cat gone.c?c2 — the blob AT c2, though absent from the wt AND the tip tree.
( cd "$WT" && "$JABC" cat "gone.c?$C2" ) >"$WORK/rev.out" 2>"$WORK/rev.err" \
    || _fail "(a) cat gone.c?c2 exited nonzero ($(cat "$WORK/rev.err"))"
grep -q 'GONE-MARKER' "$WORK/rev.out" \
    || _fail "(a) cat gone.c?c2 did not emit gone.c's bytes:
$(cat "$WORK/rev.out" "$WORK/rev.err")"
echo "ok: cat gone.c?<rev> emits the rev'd blob"

# (a2) --plain form emits the same bytes.
( cd "$WT" && "$JABC" cat --plain "gone.c?$C2" ) >"$WORK/plain.out" 2>&1 \
    || _fail "(a2) cat --plain gone.c?c2 exited nonzero"
grep -q 'GONE-MARKER' "$WORK/plain.out" \
    || _fail "(a2) cat --plain gone.c?c2 empty:
$(cat "$WORK/plain.out")"
echo "ok: cat --plain gone.c?<rev> emits the rev'd blob"

# (a3) cat: scheme form emits the same bytes.
( cd "$WT" && "$JABC" cat "cat:gone.c?$C2" ) >"$WORK/scheme.out" 2>&1 \
    || _fail "(a3) cat cat:gone.c?c2 exited nonzero"
grep -q 'GONE-MARKER' "$WORK/scheme.out" \
    || _fail "(a3) cat cat:gone.c?c2 empty:
$(cat "$WORK/scheme.out")"
echo "ok: cat cat:gone.c?<rev> emits the rev'd blob"

# (b) cat nope.c?c2 — a path ABSENT at that rev must FAIL LOUD (never silent-empty).
if ( cd "$WT" && "$JABC" cat "nope.c?$C2" ) >"$WORK/absent.out" 2>&1; then
    _fail "(b) cat nope.c?c2 exited ZERO for a path absent at that rev (silent-empty):
$(cat "$WORK/absent.out")"
fi
grep -q 'CATNOFILE' "$WORK/absent.out" \
    || _fail "(b) cat nope.c?c2 did not report CATNOFILE:
$(cat "$WORK/absent.out")"
echo "ok: cat <absent>?<rev> fails loud with CATNOFILE"

# (c) plain-wt cat a.txt — unchanged (reads the live wt file).
( cd "$WT" && "$JABC" cat a.txt ) >"$WORK/wt.out" 2>&1 \
    || _fail "(c) cat a.txt exited nonzero:
$(cat "$WORK/wt.out")"
grep -q 'INSIDE-A' "$WORK/wt.out" \
    || _fail "(c) cat a.txt did not render the wt file:
$(cat "$WORK/wt.out")"
echo "ok: plain-wt cat a.txt unchanged"

echo "PASS [$NAME]"
