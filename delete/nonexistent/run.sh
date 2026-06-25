#!/bin/sh
# test/js/delete/nonexistent — `be delete <typo>` for a path absent on disk
# AND never in the baseline: a silent no-op (no row, exit 0) reported as a
# skip in the `delete:` count.  Also covers missing-but-tracked (`rm a.txt`
# then delete → a row, no file).  Native vs JS must agree on the banner +
# rows + file set.
. "$(dirname "$0")/../deletecase.sh"

seed_baseline 'printf "A\n" > a.txt; printf "B\n" > b.txt'
fork_pair
mutate 'rm a.txt'
delete_both a.txt typo.txt

pass
