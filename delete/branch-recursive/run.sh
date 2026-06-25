#!/bin/sh
# test/js/delete/branch-recursive — `be delete -r ?<branch>` parity.  A
# branch with an active descendant (`feat` + `feat/fix1`) refuses without
# `-r`; with `-r` the subtree is dropped deepest-first (a tombstone for
# `feat/fix1` THEN `feat`).  Native vs JS must agree on the ordered refs
# tombstone rows.  Both branches are created identically before the delete.
. "$(dirname "$0")/../deletecase.sh"

seed_baseline 'printf "A\n" > a.txt'
fork_pair
mutate '"$BE" put "?feat" >/dev/null 2>&1; "$BE" put "?feat/fix1" >/dev/null 2>&1'
delete_both -r '?feat'

pass
