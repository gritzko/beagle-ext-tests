#!/bin/sh
# test/put/subdir-multi-wt — BE-032/BE-042: the subdir-multi case run inside a
# HIVE worktree cell (`$SRC_ROOT/WT1`, hive layout per BE-031/BE-037) so the nav
# context is `//WT1/sub` — the //WT/path context must not garble the cwd-context
# arg resolution: same four rows, root decoys untouched, as in put/subdir-multi.
. "$(dirname "$0")/../putcase.sh"

seed_baseline 'mkdir -p sub/d sub/f b d f
printf "A1\n" > sub/a.txt;   printf "C1\n" > b/c.txt
printf "E1\n" > sub/d/e.txt; printf "G1\n" > sub/f/g.txt
printf "dA1\n" > a.txt; printf "dE1\n" > d/e.txt; printf "dG1\n" > f/g.txt'
# BE-031 hive: the cell lives under a literal work/ dir (the topWt boundary);
# SRC_ROOT pins the hive so navCwd names the cell //WT1.
HIVE="$WORK/work"; mkdir -p "$HIVE"
SRC_ROOT="$HIVE"; export SRC_ROOT
JS="$HIVE/WT1"; rm -rf "$JS"; cp -a "$BASE" "$JS"
mutate 'sleep 0.02
printf "A2\n" > sub/a.txt;   printf "C2\n" > b/c.txt
printf "E2\n" > sub/d/e.txt; printf "G2\n" > sub/f/g.txt
printf "dA2\n" > a.txt; printf "dE2\n" > d/e.txt; printf "dG2\n" > f/g.txt'
# BE-032: run put from INSIDE the cell's sub/ — context //WT1/sub.
( cd "$JS/sub" && "$JABC" put ./a.txt ../b/c.txt ./d/e.txt f/g.txt ) >"$JS.out" 2>"$JS.err" || true
_assert_equiv

pass
