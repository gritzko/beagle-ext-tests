#!/bin/sh
# JS-094 regression: `diff:<sub>/<file>` — a file UNDER a mounted submodule.
# The file's baseline lives in the SUB's store, not the parent tree, so a
# parent-tree walk hits the gitlink and the file reads as wholly "added"
# (`@@ -1,0 ...`).  `be` recurses the mount; jab must too.  Asserts the loop's
# wt-vs-base diff of a dirtied sub file is byte-identical to `be` (--plain +
# --color, oracle `be`), name-prefixed under the mount.
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

# sub `ch` (a multi-line file so the diff has context), parent `par` pinning it.
mkg ch  || { echo "FAIL(setup): git init ch" >&2; exit 1; }
printf 'alpha\nbeta\ngamma\ndelta\n' > ch/c.txt
git -C ch add -A; git -C ch commit -qm c1
mkg par || { echo "FAIL(setup): git init par" >&2; exit 1; }
printf 'par\n' > par/p.txt
git -C par -c protocol.file.allow=always submodule add -q "$S/ch" chsub >/dev/null 2>&1 \
    || { echo "FAIL(setup): submodule add" >&2; exit 1; }
# TEST-003: point the sub's `.gitmodules` url at the GIT WIRE (ssh://localhost,
# HOME-relative) so the sub mounts over git-upload-pack, not the retired keeper.
git_submodule_url par chsub "$S/ch" >/dev/null
git -C par add -A; git -C par commit -qm p1

# TEST-003: import over the GIT WIRE (git-upload-pack) into a PRIMARY beagle store
# (mounts chsub as a sibling `.be/ch` shard with its own `.be` anchor) — no keeper.
git_ingest "$S/par" par "$S/B1" >/dev/null \
    || { echo "FAIL(setup): git-wire ingest of par into B1" >&2; exit 1; }
cd "$S/B1"
[ -f chsub/.be ] || { echo "FAIL: chsub not mounted" >&2; exit 1; }

# dirty the file INSIDE the mounted sub (inline edit + a whole-line change).
printf 'alpha\nBETA changed\ngamma\nDELTA\n' > chsub/c.txt

diff_eq "wt-vs-base of a file under a mount" 'diff:chsub/c.txt'

pass
