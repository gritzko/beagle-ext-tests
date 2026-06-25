#!/bin/sh
# test/js/post/file — `bin/post.js` vs native `be post` on the local path.
# Asserts byte-equivalent commit object, REFS row, wtlog post row, and `post:`
# banner across a mix of decisions: a modified file, a new file, a new file in
# a new subdir, a deleted file, and a kept (untouched tracked) file.
. "$(dirname "$0")/../../lib/postcase.sh"

build_origin() {
    printf 'A\n' > a.txt
    printf 'B\n' > b.txt
    printf 'KEEP\n' > keep.txt
    mkdir d; printf 'C\n' > d/c.txt
    "$BE" post '#c1' >/dev/null 2>&1
}

stage_change() {
    printf 'A2\n' > a.txt                 # mod a tracked file
    printf 'NEW\n' > new.txt              # new top-level file
    mkdir -p g; printf 'G\n' > g/g.txt    # new file in a new subdir
    rm b.txt                              # delete a tracked file
    "$BE" put a.txt new.txt g/g.txt >/dev/null 2>&1
    "$BE" delete b.txt >/dev/null 2>&1
}

post_parity build_origin stage_change 'mixed change-set'

pass
