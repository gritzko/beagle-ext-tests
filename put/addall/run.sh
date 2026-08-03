#!/bin/sh
# test/put/addall — TODO-005: the explicit `put +` form.  PUT-009 rules that a
# bare `put` never stages an untracked file; `+` is that manual staging said
# ONCE — every `unk` file in scope, and nothing else.  The mutation plants all
# four axes: a tracked-dirty file (`a.txt`, the BARE form's bucket), a deleted
# tracked one (`b.txt`, delete's bucket) and two untracked ones (`unt.txt` and
# `sub/deep.txt`, one of them a level down — the fold is whole-tree, as bare
# put's is).  `put +` must stage ONLY the two untracked ones, through the normal
# `put:` banner rows and the normal `put` wtlog rows.
# The fourth axis is the ESCAPE HATCH: a TRACKED file literally named `+` is
# modified too.  `put +` must leave it alone (the arg is the form, not the path)
# and the following `put ./+` must stage it — so no path becomes unreachable.
. "$(dirname "$0")/../putcase.sh"

seed_baseline 'printf "A\n" > a.txt; printf "B\n" > b.txt; printf "P\n" > +; mkdir sub; printf "S\n" > sub/s.txt'
fork_pair
mutate 'sleep 0.02; printf "A2\n" > a.txt; rm b.txt; printf "P2\n" > +; printf "U\n" > unt.txt; printf "D\n" > sub/deep.txt'

# the add-all fold, then the escape hatch — one golden over both runs.
( cd "$JS" && "$JABC" put +   ) >"$JS.out"  2>"$JS.err"  || true
( cd "$JS" && "$JABC" put ./+ ) >>"$JS.out" 2>>"$JS.err" || true
_assert_equiv

pass
