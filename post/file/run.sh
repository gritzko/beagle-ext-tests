#!/bin/sh
# JAB-003 test/post/file — golden snapshot of jab `post` on a mixed change-set
# (mod / new / new-subdir / delete / keep).  Native `be post` is retired as the
# oracle (jab emits a true hunk banner, native stays columnar); the shared
# post_parity now snapshots jab's own verified-correct output.
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
