#!/bin/sh
#  wire/push-nonff — GIT-013: POST is FF-only.  Clone master@A, commit C locally
#  (parent A), then advance the peer to B (server commit on top of A) so the
#  remote tip is NOT an ancestor of C.  `jab post ssh://…?master` must REFUSE
#  ("can not be fast-forwarded") and leave the bare's master UNCHANGED
#  (no force, no reset).
#  Adapts C post/05-non-ff-refused to jab.  Needs ssh-to-localhost (WITH_SSH).
. "$(dirname "$0")/../lib/wirecase.sh"

wire_push_seed
cur=$(wire_local_commit "$PWT" "$(printf 'A\nC\n')")     # client tip C (parent A)
[ -n "$cur" ] && [ "$cur" != "$PA" ] || _fail "local commit did not advance cur"
B=$(wire_peer_advance "$PBARE")                          # peer master -> B
[ "$B" != "$PA" ] && [ "$B" != "$cur" ] || _fail "peer did not advance to a divergent B"

if ( cd "$PWT" && "$JABC" post "ssh://localhost/$PREL?master" ) \
     >"$WORK/push.out" 2>"$WORK/push.err"; then
  _fail "non-FF post unexpectedly succeeded: $(cat "$WORK/push.out")"
fi
grep -q "can not be fast-forwarded" "$WORK/push.err" \
  || { echo "--- err ---"; cat "$WORK/push.err"; _fail "non-FF post did not refuse as non-FF"; }
after=$(git -C "$PBARE" rev-parse master)
[ "$after" = "$B" ] || _fail "refused non-FF post still moved the bare ($B -> $after)"
git -C "$PBARE" fsck >/dev/null 2>&1 || _fail "bare fails fsck"
pass
