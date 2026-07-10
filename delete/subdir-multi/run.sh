#!/bin/sh
# test/delete/subdir-multi — BE-032/URI-010: multiple relative path args resolve
# against the INVOCATION SUBDIR (the cwd context), re-anchored at the wt root:
# `cd sub && jab delete ./a.txt ../b/c.txt ./d/e.txt f/g.txt` unlinks sub/a.txt,
# b/c.txt, sub/d/e.txt, sub/f/g.txt.  Root decoys a.txt / d/e.txt / f/g.txt must
# SURVIVE — pre-fix the bare args unlinked those wrong files (destructive).
. "$(dirname "$0")/../deletecase.sh"

seed_baseline 'mkdir -p sub/d sub/f b d f
printf "A1\n" > sub/a.txt;   printf "C1\n" > b/c.txt
printf "E1\n" > sub/d/e.txt; printf "G1\n" > sub/f/g.txt
printf "dA1\n" > a.txt; printf "dE1\n" > d/e.txt; printf "dG1\n" > f/g.txt'
fork_pair
# BE-032: run delete from INSIDE sub/ — cross-dir relative args, ./ ../ and bare.
( cd "$JS/sub" && "$JABC" delete ./a.txt ../b/c.txt ./d/e.txt f/g.txt ) >"$JS.out" 2>"$JS.err" || true
_assert_equiv

pass
