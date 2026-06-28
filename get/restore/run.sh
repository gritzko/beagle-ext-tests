#!/bin/sh
# test/get/restore — DIS-055 D4: `be get file.c` restores ONE file from cur's
# baseline; `be get file.c?feat` restores it from another branch's tip.  Only
# the named path is touched — siblings stay as-is.  GET.mkd pt 1 / CLI `file.c`.
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC=$(gr_src src)
gr_jclone "$SRC" "$WORK/jT"

# Dirty TWO files; `be get a.txt` must restore ONLY a.txt (b.txt stays dirty).
printf 'DIRTY-A\n' > "$WORK/jT/a.txt"
printf 'DIRTY-B\n' > "$WORK/jT/b.txt"
rc=$(gr_jget "$WORK/jT" a.txt)
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get a.txt exit=$rc"; }
gr_file_is "$WORK/jT/a.txt" "A"          # restored from baseline
gr_file_is "$WORK/jT/b.txt" "DIRTY-B"    # untouched (scope = a.txt only)

# Subtree restore: dirty d/c.txt, `be get d` restores the whole d/ subtree.
printf 'DIRTY-C\n' > "$WORK/jT/d/c.txt"
rc=$(gr_jget "$WORK/jT" d)
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get d exit=$rc"; }
gr_file_is "$WORK/jT/d/c.txt" "C"

pass
