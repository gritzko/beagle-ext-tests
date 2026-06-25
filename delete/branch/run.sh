#!/bin/sh
# test/js/delete/branch — `be delete ?<branch>` (branch tombstone) parity.
# A leaf branch label is dropped via a REFS `delete ?br#0…0` tombstone (no
# wt change).  Native vs JS must agree on the project-shard refs rows and
# the (empty) wtlog delete rows.  The branch is created identically on both
# sides via native `be put ?feat` before the differential delete.
. "$(dirname "$0")/../deletecase.sh"

seed_baseline 'printf "A\n" > a.txt'
fork_pair
mutate '"$BE" put "?feat" >/dev/null 2>&1'
delete_both '?feat'

pass
