#!/bin/sh
#  post/push-unrelated — POST-027 cell 5-v (unrelated): the peer's master holds
#  a DISJOINT history (no common base with cur).  Clone master@A, commit C
#  locally, then force-replace the peer's master with a parentless commit U
#  from a fresh seed.  `jab post ssh://…?master` must refuse POSTNOFF — the
#  local FF walk from cur never finds U (it is not even in the local DAG), and
#  pushRemote (verbs/post/post.js:424-499) stays FF-only — and the peer must be
#  UNCHANGED.  Spec: /wiki/POST.mkd §"Summary of invocation patterns" row 5
#  (every tip motion is a fast-forward).  Needs ssh-to-localhost (WITH_SSH).
. "$(dirname "$0")/../../wire/lib/wirecase.sh"

wire_push_seed
cur=$(wire_local_commit "$PWT" "$(printf 'A\nC\n')")     # client tip C (parent A)
[ -n "$cur" ] && [ "$cur" != "$PA" ] || _fail "local commit did not advance cur"

#  A disjoint root U (fresh repo, no shared ancestor), force-planted as master.
_us="$WORK/useed"; git init -q -b master "$_us"
git -C "$_us" config user.email t@e.st; git -C "$_us" config user.name T
printf 'U\n' > "$_us/u.txt"; git -C "$_us" add -A
git -C "$_us" commit -qm U >/dev/null 2>&1
git -C "$_us" push -qf "$PBARE" master:master >/dev/null 2>&1
U=$(git -C "$PBARE" rev-parse master)
[ "$U" != "$PA" ] && [ "$U" != "$cur" ] || _fail "peer did not switch to a disjoint U"

if ( cd "$PWT" && "$JABC" post "ssh://localhost/$PREL?master" ) \
     >"$WORK/push.out" 2>"$WORK/push.err"; then
  _fail "unrelated-history post unexpectedly succeeded: $(cat "$WORK/push.out")"
fi
grep -q "can not be fast-forwarded" "$WORK/push.err" \
  || { echo "--- err ---"; cat "$WORK/push.err"; _fail "unrelated post did not refuse via the non-FF report"; }
after=$(git -C "$PBARE" rev-parse master)
[ "$after" = "$U" ] || _fail "refused unrelated post still moved the bare ($U -> $after)"
git -C "$PBARE" fsck >/dev/null 2>&1 || _fail "bare fails fsck"
pass
