#!/bin/sh
# test/get/restore-deleted — GET-047 × GET.mkd 2.3: a narrowed `get <path>`
# RECOVERS a DELETED path from cur's baseline (the spec's "(recovers)") — an
# rm'd file comes back, an rm -r'd dir comes back as a whole subtree; a dirty
# sibling outside the narrow is untouched.  (get/restore covers MANGLED only.)
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC=$(gr_src src)
gr_jclone "$SRC" "$WORK/jT"

# Deleted FILE: rm a.txt (dirty b.txt is the outside-the-narrow control).
rm "$WORK/jT/a.txt"
printf 'DIRTY-B\n' > "$WORK/jT/b.txt"
rc=$(gr_jget "$WORK/jT" a.txt)
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get a.txt exit=$rc"; }
gr_file_is "$WORK/jT/a.txt" "A"          # recovered from cur's baseline
gr_file_is "$WORK/jT/b.txt" "DIRTY-B"    # untouched (scope = a.txt only)

# Deleted DIR: rm -r d/, `get d/` restores the whole subtree.
rm -r "$WORK/jT/d"
rc=$(gr_jget "$WORK/jT" d/)
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get d/ exit=$rc"; }
gr_file_is "$WORK/jT/d/c.txt" "C"

pass
