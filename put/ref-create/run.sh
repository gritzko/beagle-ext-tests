#!/bin/sh
# test/js/put/ref-create — `be put ?<branch>` (branch-form create) parity.
# Creates the named branch as a label at cur.tip with no commit: a pure REFS
# `post ?<branch>#<cur-tip>` row, NO stdout banner.  Native vs JS must agree
# on the (empty) stdout and the project-shard refs row.
. "$(dirname "$0")/../putcase.sh"

seed_baseline 'printf "A\n" > a.txt'
fork_pair
put_both '?feat'

pass
