#!/bin/sh
# test/put/subdir-multi — BE-032/URI-010: multiple relative path args resolve
# against the INVOCATION SUBDIR (the cwd context), re-anchored at the wt root:
# `cd sub && jab put ./a.txt ../b/c.txt ./d/e.txt f/g.txt` stages sub/a.txt,
# b/c.txt, sub/d/e.txt, sub/f/g.txt.  Root decoys a.txt / d/e.txt / f/g.txt
# (dirty too) must stay UNSTAGED — pre-fix the bare args hit those wrong files.
. "$(dirname "$0")/../putcase.sh"

seed_baseline 'mkdir -p sub/d sub/f b d f
printf "A1\n" > sub/a.txt;   printf "C1\n" > b/c.txt
printf "E1\n" > sub/d/e.txt; printf "G1\n" > sub/f/g.txt
printf "dA1\n" > a.txt; printf "dE1\n" > d/e.txt; printf "dG1\n" > f/g.txt'
fork_pair
mutate 'sleep 0.02
printf "A2\n" > sub/a.txt;   printf "C2\n" > b/c.txt
printf "E2\n" > sub/d/e.txt; printf "G2\n" > sub/f/g.txt
printf "dA2\n" > a.txt; printf "dE2\n" > d/e.txt; printf "dG2\n" > f/g.txt'
# BE-032: run put from INSIDE sub/ — cross-dir relative args, ./ ../ and bare.
( cd "$JS/sub" && "$JABC" put ./a.txt ../b/c.txt ./d/e.txt f/g.txt ) >"$JS.out" 2>"$JS.err" || true
_assert_equiv

pass
