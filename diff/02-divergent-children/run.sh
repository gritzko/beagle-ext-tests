#!/bin/sh
# TEST-003 jab-intrinsic: divergent children — a base then two branches editing
# DISJOINT lines, then the cross-branch range diff both ways.  Native `be`/`graf`
# RETIRED (they LAG jab); diff_eq asserts jab's own `--plain`/`--color` + have.
# jab seed: post to a NAMED ref (`post -m e1 '?fix1'` advances fix1 — a bare
# `post` lands on the empty branch); return to base via `?base` (jab lacks `?..`).
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt p)
cd "$W"

# TEST-003: bootstrap base with a bare-post to a named `?base` (no pre-put).
printf 'line one\nline two\nline three\nline four\nline five\n' > foo.c
"$BE" post -m base '?base' >/dev/null 2>&1
# DIS-076: a message-post never mints/moves a ref — publish the tag explicitly
# (the `post "?<branch>"` pattern) so `?base`/`?fix1`/`?fix2` stay resolvable.
"$BE" post '?base' >/dev/null 2>&1

# branch fix1 off base, edit line one, post ONTO ?fix1.
"$BE" put '?fix1' >/dev/null 2>&1
sleep 0.02
printf 'LINE ONE edited\nline two\nline three\nline four\nline five\n' > foo.c
"$BE" put foo.c >/dev/null 2>&1
"$BE" post -m e1 '?fix1' >/dev/null 2>&1
"$BE" post '?fix1' >/dev/null 2>&1

# back to base, branch fix2, edit line five, post ONTO ?fix2.
"$BE" get '?base'   >/dev/null 2>&1
"$BE" put '?fix2' >/dev/null 2>&1
sleep 0.02
printf 'line one\nline two\nline three\nline four\nLINE FIVE edited\n' > foo.c
"$BE" put foo.c >/dev/null 2>&1
"$BE" post -m e2 '?fix2' >/dev/null 2>&1
"$BE" post '?fix2' >/dev/null 2>&1

diff_eq "tree fix1..fix2 (canonical)" 'diff:?fix1..fix2'
have 'LINE ONE edited'  "fix1..fix2: fix1's line-one edit"
have 'LINE FIVE edited' "fix1..fix2: fix2's line-five edit"
diff_eq "tree fix2..fix1 (reverse)"   'diff:?fix2..fix1'
have 'LINE ONE edited'  "fix2..fix1: reverse still shows both edits"
diff_eq "file fix1..fix2"             'diff:foo.c?fix1..fix2'
have 'LINE ONE edited'  "file fix1..fix2: file-scoped edit"

pass
