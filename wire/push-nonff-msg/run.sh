#!/bin/sh
#  GIT-016 wire/push-nonff-msg — T1 honest non-FF message (verbs/post/post.js
#  pushRemote).  A non-FF `jab post` refuses "can not be fast-forwarded" and
#  NOTHING more: no `force` hint (post is FF-only) and no diverged/unrelated
#  guess (remote ancestry is unwalked on the push side).  Models
#  wire/push-nonff; needs ssh.
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
#  T1: the message names the non-FF and is HONEST — no force hint, no
#  diverged/unrelated claim (the push side does not walk remote ancestry).
grep -q "can not be fast-forwarded" "$WORK/push.err" \
  || { echo "--- err ---"; cat "$WORK/push.err"; _fail "non-FF post did not refuse as non-FF"; }
if grep -qi force "$WORK/push.err"; then
  echo "--- err ---"; cat "$WORK/push.err"; _fail "non-FF msg wrongly hints 'force'"
fi
if grep -qiE 'diverg|unrelated' "$WORK/push.err"; then
  echo "--- err ---"; cat "$WORK/push.err"; _fail "non-FF msg wrongly claims diverged/unrelated"
fi
after=$(git -C "$PBARE" rev-parse master)
[ "$after" = "$B" ] || _fail "refused non-FF post still moved the bare ($B -> $after)"
git -C "$PBARE" fsck >/dev/null 2>&1 || _fail "bare fails fsck"
pass
