#!/bin/sh
# test/js/put/move — `be put <old>#<new>` (explicit move) parity.  The
# rename-in-flight shape: src on disk, dst free → put.js renames on disk and
# writes one `put <old>#<new>` row whose fragment is the dst path, stamping
# the dst file.  Native vs JS must agree on the banner, the move row, the
# on-disk rename, and the restamp.
. "$(dirname "$0")/../putcase.sh"

seed_baseline 'printf "A\n" > a.txt; printf "B\n" > b.txt'
fork_pair
mutate 'sleep 0.02'
put_both 'b.txt#moved.txt'

pass
