#!/bin/sh
# test/js/put/ref-set — `be put ?<branch>#<sha>` (branch-form set, OUTRIGHT)
# parity.  PUT is unconstrained: setting `?feat` to the PARENT commit (a
# non-FF backward move) writes the ref directly.  Native vs JS must agree on
# the project-shard refs row and the (empty) stdout.  Two commits give a
# parent sha to set to.
. "$(dirname "$0")/../putcase.sh"

# Baseline with TWO commits so a parent sha exists.
seed_baseline 'printf "A\n" > a.txt'
( cd "$BASE" && sleep 0.02 && printf "A2\n" > a.txt && \
  "$BE" put a.txt >/dev/null 2>&1 && "$BE" post c2 >/dev/null 2>&1 )

# Resolve the parent sha (cur.tip's first parent) from the baseline.
PAR=$("$JABC" "$(dirname "$0")/../parentsha.js" "$BASE")
[ -n "$PAR" ] || _fail "could not resolve parent sha"

fork_pair
put_both "?feat#$PAR"

pass
