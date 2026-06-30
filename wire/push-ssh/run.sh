#!/bin/sh
#  wire/push-ssh — GIT-013: `jab post ssh://localhost/<bare>?master` FF-pushes
#  cur's tip onto a LOCAL bare repo's master over the JS receive-pack send-pack
#  (shared/wire.js push).  Clone a git bare into a be worktree, commit a FF
#  descendant locally, then push: the bare's master must advance to cur and the
#  bare must stay fsck-clean.  Adapts C post/31-remote-branch-push to jab.  Needs
#  ssh-to-localhost (WITH_SSH).
. "$(dirname "$0")/../lib/wirecase.sh"

wire_push_seed
cur=$(wire_local_commit "$PWT" "$(printf 'A\nB\n')")
[ -n "$cur" ] && [ "$cur" != "$PA" ] || _fail "local commit did not advance cur"

( cd "$PWT" && "$JABC" post "ssh://localhost/$PREL?master" ) \
  >"$WORK/push.out" 2>"$WORK/push.err" \
  || { echo "--- err ---"; cat "$WORK/push.err"; _fail "ssh FF push failed"; }

after=$(git -C "$PBARE" rev-parse master)
[ "$after" = "$cur" ] || _fail "bare master did not FF-advance to cur ($cur; got $after)"
git -C "$PBARE" fsck >/dev/null 2>&1 || _fail "pushed bare fails fsck"
pass
