#!/bin/sh
#  wire/put-force-ssh — GIT-014: `jab put ssh://…?master` is the UNCONSTRAINED
#  remote ref-write (NO FF gate).  Clone master@A, commit C locally (parent A),
#  advance the peer to B (divergent) — so a POST would refuse the non-FF — then
#  `jab put` FORCE-resets the peer's master to cur (C), a NON-FF move POST will
#  not do.  Asserts the bare's master == cur after, and stays fsck-clean.  Needs
#  ssh-to-localhost (WITH_SSH).
. "$(dirname "$0")/../lib/wirecase.sh"

wire_push_seed
cur=$(wire_local_commit "$PWT" "$(printf 'A\nC\n')")     # client tip C (parent A)
[ -n "$cur" ] && [ "$cur" != "$PA" ] || _fail "local commit did not advance cur"
B=$(wire_peer_advance "$PBARE")                          # peer master -> B (divergent)
[ "$B" != "$cur" ] || _fail "peer did not diverge from cur"

#  POST must REFUSE this non-FF (the contrast PUT overrides).
if ( cd "$PWT" && "$JABC" post "ssh://localhost/$PREL?master" ) \
     >"$WORK/post.out" 2>"$WORK/post.err"; then
  _fail "POST non-FF unexpectedly succeeded (should refuse, PUT forces instead)"
fi
grep -q "can not be fast-forwarded" "$WORK/post.err" || _fail "POST did not refuse the non-FF"
[ "$(git -C "$PBARE" rev-parse master)" = "$B" ] || _fail "refused POST moved the bare"

#  PUT FORCE: reset the peer's master to cur — a NON-FF move (no ancestor gate).
( cd "$PWT" && "$JABC" put "ssh://localhost/$PREL?master" ) \
  >"$WORK/put.out" 2>"$WORK/put.err" \
  || { echo "--- err ---"; cat "$WORK/put.err"; _fail "ssh force put failed"; }
after=$(git -C "$PBARE" rev-parse master)
[ "$after" = "$cur" ] || _fail "force put did not reset bare master to cur ($cur; got $after)"
git -C "$PBARE" fsck >/dev/null 2>&1 || _fail "pushed bare fails fsck"
pass
