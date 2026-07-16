#!/bin/sh
#  post/push-fresh — POST-027 matrix row "5 POSTNONE: push from a fresh
#  never-committed wt (pushRemote post.js:425)".  A fresh worktree (empty-`.be`
#  shield, zero commits) has no cur tip — `jab post ssh://…?master` must refuse
#  POSTNONE "no cur tip to push" before touching the wire, and the peer must be
#  unchanged.  Spec: /wiki/POST.mkd §"Summary of invocation patterns" row 5
#  pushes "cur's EXISTING tip"; with none there is nothing to ship.  The fresh
#  wt uses the ONE shield procedure (rs_wt_at, test/lib/repo-setup.sh).  Needs
#  ssh-to-localhost (WITH_SSH — for the peer fixture only).
. "$(dirname "$0")/../../wire/lib/wirecase.sh"

wire_push_seed
rs_wt_at "$WORK/fresh"                                   # never-committed wt

if "$JABC" post "ssh://localhost/$PREL?master" \
     >"$WORK/push.out" 2>"$WORK/push.err"; then
  _fail "fresh-wt post unexpectedly succeeded: $(cat "$WORK/push.out")"
fi
grep -q "no cur tip to push" "$WORK/push.err" \
  || { echo "--- err ---"; cat "$WORK/push.err"; _fail "refusal is not the 'no cur tip' report"; }
after=$(git -C "$PBARE" rev-parse master)
[ "$after" = "$PA" ] || _fail "fresh-wt refusal still moved the bare ($PA -> $after)"
git -C "$PBARE" fsck >/dev/null 2>&1 || _fail "bare fails fsck"
pass
