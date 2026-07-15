#!/bin/sh
# test/delete/subdir-multi-wt — BE-032/BE-042: the subdir-multi delete case run
# inside a worktree under work/ (`$SRC_ROOT/WT1`, BE-031/BE-037) so the nav context
# is `//WT1/sub` — the //WT/path context must not garble the cwd-context arg
# resolution: same four unlinks, root decoys survive, as in delete/subdir-multi.
. "$(dirname "$0")/../deletecase.sh"

seed_baseline 'mkdir -p sub/d sub/f b d f
printf "A1\n" > sub/a.txt;   printf "C1\n" > b/c.txt
printf "E1\n" > sub/d/e.txt; printf "G1\n" > sub/f/g.txt
printf "dA1\n" > a.txt; printf "dE1\n" > d/e.txt; printf "dG1\n" > f/g.txt'
# BE-031: the wt lives under a literal work/ dir (the topWt boundary);
# SRC_ROOT pins the work/ dir so navCwd names the wt //WT1.
WORKD="$WORK/work"; mkdir -p "$WORKD"
SRC_ROOT="$WORKD"; export SRC_ROOT
JS="$WORKD/WT1"; rm -rf "$JS"; cp -a "$BASE" "$JS"
# BE-032: run delete from INSIDE the wt's sub/ — context //WT1/sub.
( cd "$JS/sub" && "$JABC" delete ./a.txt ../b/c.txt ./d/e.txt f/g.txt ) >"$JS.out" 2>"$JS.err" || true
_assert_equiv

pass
