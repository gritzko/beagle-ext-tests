#!/bin/sh
# test/get/rewind — DIS-055 D3: `be get '#~1'` rewinds cur's ref N commits
# (first-parent walk) and resets the wt, STAYING attached to cur.  GET.mkd CLI
# `#~1`.  A two-commit source: after a clone at c2, `#~1` walks to c1 and resets
# the wt to c1's tree (a.txt=A, no z.txt), the new cur tip = c1.
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC=$(gr_src src)
C1=$(gr_tip_sha "$SRC")

cd "$SRC"
printf 'A2\n' > a.txt; printf 'Z\n' > z.txt
"$BE" put a.txt z.txt >/dev/null 2>&1
"$BE" post 'c2' >/dev/null 2>&1
C2=$(gr_tip_sha "$SRC")
[ "$C1" != "$C2" ] || _fail "c2 did not advance"

gr_jclone "$SRC" "$WORK/jT"
gr_file_is "$WORK/jT/a.txt" "A2"

rc=$(gr_jget "$WORK/jT" '#~1')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get #~1 exit=$rc"; }
gr_file_is "$WORK/jT/a.txt" "A"
[ ! -e "$WORK/jT/z.txt" ] || _fail "#~1 left z.txt (a c2-only file)"

# cur's tip is now c1 (attached): a fragment-pin or branch row carrying c1.
gr_wtlog_has "$WORK/jT" "$C1"

pass
