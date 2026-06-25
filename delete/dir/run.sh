#!/bin/sh
# test/js/delete/dir — `be delete <dir>/` (dir-form recursive removal)
# parity.  Every tracked file under the prefix is unlinked and ONE
# `delete <dir>/` row is appended; files outside the prefix untouched.
# Native vs JS must agree on the banner, the row, and the file set.
. "$(dirname "$0")/../deletecase.sh"

seed_baseline 'mkdir src; printf "C\n" > src/a.c; printf "D\n" > src/b.c; printf "R\n" > README.md'
fork_pair
delete_both 'src/'

pass
