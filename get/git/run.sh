#!/bin/sh
# test/js/get/git — `bin/get.js` vs native `be get` over an ssh:// remote
# pointing at a vanilla GIT repo (git-upload-pack interop).  Asserts
# equivalent stdout + worktree + `be status` for a fresh clone and a
# git mod/new/del update.  Needs git + ssh-to-localhost (gated WITH_SSH).
. "$(dirname "$0")/../../lib/getcase.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP [git] no git"; exit 0; }

REPO="$WORK/repo"
mkdir -p "$REPO"; cd "$REPO"
git init -q
git config user.email t@e.st; git config user.name Test
printf 'A\n' > a.txt; printf 'B\n' > b.txt; mkdir d; printf 'C\n' > d/c.txt
git add -A; git commit -qm c1

case "$REPO" in
    "$HOME"/*) RELREPO="${REPO#$HOME/}" ;;
    *) echo "SKIP [git] scratch not under \$HOME"; exit 0 ;;
esac
REMOTE="ssh://localhost/$RELREPO?/repo"
mkdir "$WORK/nT" "$WORK/jT"

get_both "$REMOTE" "$WORK/nT" "$WORK/jT"
status_both "$WORK/nT" "$WORK/jT"

# git update: mod a.txt, new n.txt, del b.txt.
cd "$REPO"
printf 'A2\n' > a.txt; printf 'N\n' > n.txt; git rm -q b.txt
git add -A; git commit -qm c2

get_both "$REMOTE" "$WORK/nT" "$WORK/jT"
status_both "$WORK/nT" "$WORK/jT"

pass
