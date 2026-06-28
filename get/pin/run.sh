#!/bin/sh
# test/get/pin — DIS-055 D1: `?branch#<sha>` (and `?#<sha>`) checks out the
# PINNED commit, not just the branch tip.  GET.mkd pt 2: Fragment is a sha pin.
# A two-commit source: pinning commit 1 must restore the OLD tree (a.txt=A),
# even though the branch tip is commit 2 (a.txt=A2).
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC=$(gr_src src)
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"

# advance the source: a.txt A->A2, add z.txt.
cd "$SRC"
printf 'A2\n' > a.txt; printf 'Z\n' > z.txt
"$BE" put a.txt z.txt >/dev/null 2>&1
"$BE" post 'c2' >/dev/null 2>&1
C2=$(gr_tip_sha "$SRC")
[ "$C1" != "$C2" ] || _fail "c2 did not advance"

# Clone (lands at c2 tip: a.txt=A2, z.txt=Z present).
gr_jclone "$SRC" "$WORK/jT"
gr_file_is "$WORK/jT/a.txt" "A2"

# Pin commit 1 via `?#<c1>` — must restore a.txt=A and REMOVE z.txt (not in c1).
rc=$(gr_jget "$WORK/jT" "?#$C1")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get ?#<c1> exit=$rc"; }
gr_file_is "$WORK/jT/a.txt" "A"
[ ! -e "$WORK/jT/z.txt" ] || _fail "pin to c1 left z.txt (a c2-only file)"

# The pin row keeps the fragment (`#<c1>`) — an exact-commit pin, attached.
gr_wtlog_has "$WORK/jT" "#$C1"

pass
