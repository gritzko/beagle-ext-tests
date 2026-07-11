#!/bin/sh
# DIFF-013 test/diff/16-bare-cwd-scope — bare `jab diff` run from a SUBDIR cwd must
# diff only that subtree (the run's context dir, be.ctxDir), NOT the whole wt.  An
# explicit `diff <dir>` already scoped (DIFF-012); bare diff ignored the cwd and
# dumped every dir.  RED-first: from sub/, bare diff must show sub/ only.
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

mkdir -p sub other
printf 'alpha\nbeta\n' > sub/in.c
printf 'omega\n' > other/out.c
"$BE" post -m base >/dev/null 2>&1

# dirty BOTH dirs: a cwd scope must show sub/ only, never other/.
printf 'alpha\nBETA mod\n' > sub/in.c
printf 'OMEGA mod\n' > other/out.c

# bare `jab diff` (NO arg) from the sub/ cwd (diff_jab runs from $PWD).
cd "$W/sub"
diff_jab "bare diff @sub"
have 'BETA mod'  "bare @sub: sub/ edit present"
miss 'OMEGA'     "bare @sub: other/ edit absent"

# from the wt ROOT bare diff stays whole-wt (unchanged): both edits present.
cd "$W"
diff_jab "bare diff @root"
have 'BETA mod'  "bare @root: sub/ edit present (whole-wt)"
have 'OMEGA mod' "bare @root: other/ edit present (whole-wt)"

pass
