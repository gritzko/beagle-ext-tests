#!/bin/sh
# DIFF-001 + the be sub pin-range relay: submodule PIN-BUMP commit.  A commit
# whose change is a gitlink bump renders the gitlink line `<sub> <old>..<new>`
# FOLLOWED by the sub's content diff for the pin range (`<sub>/<file>: v1 -> v2`),
# path-prefixed under the mount; `--nosub` keeps the gitlink line but drops the
# sub content.  TEST-003: jab-intrinsic --plain — native `be` LAGS jab, so assert
# the pin-bump hunk SHAPE jab emits (gitlink line + prefixed sub diff), not a cmp.
. "$(dirname "$0")/../lib/diffcase.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git not found" >&2; exit 0; }
# TEST-003: git-wire ingest (git-upload-pack, NO keeper) needs ssh-to-localhost
# and the scratch under $HOME (git-over-ssh is HOME-relative).
git_ssh_ok || { echo "SKIP: no git/ssh-to-localhost for the git-wire ingest" >&2; exit 0; }
case "$WORK" in "$HOME"/*) ;; *) echo "SKIP: scratch not under \$HOME (git-over-ssh)" >&2; exit 0 ;; esac
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
# TEST-003: point the sub's `.gitmodules` url at the GIT WIRE (ssh://localhost,
# HOME-relative) so the sub mounts over git-upload-pack, not the retired keeper.
git_submodule_url par chsub "$S/ch" >/dev/null
git -C par add -A; git -C par commit -qm p1
printf 'v2\n' > ch/c.txt; git -C ch add -A; git -C ch commit -qm c2
C2=$(git -C ch rev-parse HEAD)
git -C par/chsub fetch -q origin >/dev/null 2>&1
git -C par/chsub checkout -q "$C2"
git -C par add chsub; git -C par commit -qm 'bump chsub'

# TEST-003: import over the GIT WIRE (git-upload-pack) into a PRIMARY beagle store
# — no `be:`/keeper.  git_ingest clones `ssh://localhost/<par>?/par` and echoes the
# trunk tip (the pin-bump commit); the submodule mounts as a sibling `.be/ch` shard.
TIP=$(git_ingest "$S/par" par "$S/B1") \
    || { echo "FAIL(setup): git-wire ingest of par into B1" >&2; exit 1; }
cd "$S/B1"
[ -n "$TIP" ] || { echo "FAIL: B1 has no tip" >&2; exit 1; }

# TEST-003: jab-intrinsic (native `be` LAGS jab, so no oracle cmp).  The invariant
# is the pin-bump SHAPE: a gitlink line `<sub> <old40>..<new40>` then the sub's
# content diff for the pin range, path-prefixed under the mount; `--nosub` keeps
# the gitlink line but DROPS the sub content — asserted on jab's own output.

# commit-show of the pin bump: gitlink line + the sub content diff, prefixed.
diff_jab "pin-bump commit-show (sub recursion)" "diff:?$TIP"
have '^chsub [0-9a-f]{40}\.\.[0-9a-f]{40}$' "pin-bump: gitlink <sub> <old>..<new> line"
have '^\+\+\+ b/chsub/c\.txt$' "pin-bump: sub content diff, path-prefixed under the mount"
have '^\+v2$' "pin-bump: sub's new content (v2) in the pin range"
have '^-v1$' "pin-bump: sub's old content (v1) in the pin range"

# --nosub: gitlink line kept, sub content dropped (no chsub/c.txt hunk).
diff_jab "pin-bump --nosub (gitlink only)" "diff:?$TIP" --nosub
have '^chsub [0-9a-f]{40}\.\.[0-9a-f]{40}$' "--nosub: gitlink line still present"
miss '^\+\+\+ b/chsub/c\.txt$' "--nosub: sub content diff must be dropped"
miss '^\+v2$' "--nosub: no sub content lines"

pass
