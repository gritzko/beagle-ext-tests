#!/bin/sh
# test/js/delete/file — `be delete <file>` (file-form removal) parity.
# Delete one tracked file present on disk: native vs JS must agree on the
# `delete:` banner, the wtlog `delete` row, and the on-disk file set (the
# named file unlinked, its sibling untouched).
. "$(dirname "$0")/../deletecase.sh"

seed_baseline 'printf "A\n" > a.txt; printf "B\n" > b.txt'
fork_pair
delete_both a.txt

pass
