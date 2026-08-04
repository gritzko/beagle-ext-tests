#!/bin/sh
# test/get/equal-stamp — GET-059: a file the get CONTENT-TESTED and proved
# byte-equal to the incoming target (the `checkout.leafUnchanged` skip at
# get.js's flat leaf) is the new baseline blob, exactly like a file get
# WROTE (GET-049) — so it must leave carrying the get row's ts as its mtime.
# The wt reaching the target on its own is the everyday case: an editor, a
# rebuild, an out-of-band patch, or a second wt on the same box.
# RED before the fix: the tested-equal files return UNSTAMPED (mtimes off the
# wtlog stamp-set), so EVERY later `be status` re-opens and re-hashes them —
# get paid for the content test, then threw the verdict away.
# The controls in the same run:
#   - keep.txt  merkle-PRUNED (unchanged c1->c2, never visited): no new read,
#               its clone stamp still holds — the ruling adds ZERO reads.
#   - f.txt     a genuine local edit that weaves clean but != the target:
#               still dirty vs the new base, so it must NEVER be stamped.
. "$(dirname "$0")/../../lib/getrepro.sh"

# c1: the shared baseline.
SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A1\n' > a.txt
printf 'B1\n' > b.txt
printf 'K\n'  > keep.txt
mkdir d; printf 'one\ntwo\nthree\n' > d/f.txt
"$BE" post 'c1' >/dev/null 2>&1
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "c1 setup"

DST="$WORK/wt"; mkdir -p "$DST"
( cd "$DST" && "$JABC" get "file://$SRC/.be#$C1" ) >/dev/null 2>&1 || _fail "clone"

# c2: a.txt, b.txt, d/f.txt advance; keep.txt is identical in both trees.
cd "$SRC"
printf 'A2\n' > a.txt
printf 'B2\n' > b.txt
printf 'ONE\ntwo\nthree\n' > d/f.txt
"$BE" post 'c2' >/dev/null 2>&1
C2=$(gr_tip_sha "$SRC")
[ -n "$C2" ] && [ "$C2" != "$C1" ] || _fail "c2 setup"

# The wt REACHES c2's bytes on its own, with mtimes OFF the stamp set (the
# git-checkout / editor mtimes the ticket measured).
printf 'A2\n' > "$DST/a.txt"
printf 'B2\n' > "$DST/b.txt"
touch -t 202001010000 "$DST/a.txt" "$DST/b.txt"
# The dirty control: an edit at a DIFFERENT anchor — weaves clean, != target.
printf 'one\ntwo\nthree\nfour\n' > "$DST/d/f.txt"

( cd "$DST" && "$JABC" get "file://$SRC/.be#$C2" ) >"$WORK/get.out" 2>"$WORK/get.err" \
    || { cat "$WORK/get.err"; _fail "get c2"; }

"$JABC" "$_CASE/assert.js" "$DST" -clean a.txt b.txt keep.txt -dirty d/f.txt \
    || _fail "tested-equal files unstamped, re-read, or a dirty file stamped"

pass
