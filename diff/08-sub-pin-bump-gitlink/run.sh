#!/bin/sh
# JAB-014 parity: submodule PIN-BUMP commit (DIFF-001 + the be sub pin-range
# relay).  A commit whose change is a gitlink bump renders the gitlink line
# `<sub> <old>..<new>` FOLLOWED by the sub's content diff for the pin range
# (`<sub>/<file>: v1 -> v2`), path-prefixed under the mount; `--nosub` keeps
# the gitlink line but drops the sub content.  Mirrors
# beagle/test/diff/08-sub-pin-bump-gitlink.  --plain only: graf has no `--at`
# baseline for a commit-show, and `be --color` pages via bro (a different
# render) — the --plain leg (oracle `be`, which composes the baseline + drives
# the be sub fan-out) is the producer-parity gate.
. "$(dirname "$0")/../lib/diffcase.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git not found" >&2; exit 0; }
export GIT_CONFIG_GLOBAL=/dev/null

S="$WORK/git"; rm -rf "$S"; mkdir -p "$S"; cd "$S"
mkg() {
    git init -q -b master "$1" >/dev/null 2>&1 || return 1
    git -C "$1" config user.email t@t
    git -C "$1" config user.name  T
    git -C "$1" config protocol.file.allow always
}

# sub `ch` at c1; parent `par` pinning chsub→c1; advance sub to c2; bump pin.
mkg ch  || { echo "FAIL(setup): git init ch" >&2; exit 1; }
printf 'v1\n' > ch/c.txt; git -C ch add -A; git -C ch commit -qm c1
mkg par || { echo "FAIL(setup): git init par" >&2; exit 1; }
printf 'par\n' > par/p.txt
git -C par -c protocol.file.allow=always submodule add -q "$S/ch" chsub >/dev/null 2>&1 \
    || { echo "FAIL(setup): submodule add" >&2; exit 1; }
git -C par add -A; git -C par commit -qm p1
printf 'v2\n' > ch/c.txt; git -C ch add -A; git -C ch commit -qm c2
C2=$(git -C ch rev-parse HEAD)
git -C par/chsub fetch -q origin >/dev/null 2>&1
git -C par/chsub checkout -q "$C2"
git -C par add chsub; git -C par commit -qm 'bump chsub'

# clone into a beagle store; the tip is the pin-bump commit.
mkdir -p "$S/B1/.be"
( cd "$S/B1" && "$BE" get "be:$S/par" >/dev/null 2>&1 ) \
    || { echo "FAIL(setup): clone par into B1" >&2; exit 1; }
cd "$S/B1"
TIP=$("$BE" sha1:'?master' 2>/dev/null)
[ -n "$TIP" ] || { echo "FAIL: B1 has no tip" >&2; exit 1; }

# commit-show of the pin bump: gitlink line + the sub content diff, prefixed.
diff_eq "pin-bump commit-show (sub recursion)" "diff:?$TIP"
# --nosub: gitlink line kept, sub content dropped.
diff_eq "pin-bump --nosub (gitlink only)"      "diff:?$TIP" --nosub

pass
