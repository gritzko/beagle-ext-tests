#!/bin/sh
#  post/push-noref — POST-027 matrix row "5: `?`-less host URI refusal
#  (relate.js, zero tests)".  `jab post ssh://…/repo.git` with NO query slot
#  selects no branch — the relate spine (shared/relate.js) refuses with
#  "no remote branch selected (`?branch`)" before any ref resolve or pack
#  build, re-raised by pushRemote.  Spec: /wiki/POST.mkd §"Summary of invocation
#  patterns" row 5 spells the push form as `ssh://host?br` — the branch slot
#  is mandatory.  Nothing may be pushed: master stays at A, no new refs.
#  Needs ssh-to-localhost (WITH_SSH).
. "$(dirname "$0")/../../wire/lib/wirecase.sh"

wire_push_seed
cur=$(wire_local_commit "$PWT" "$(printf 'A\nQ\n')")     # a real tip to (not) push
[ -n "$cur" ] && [ "$cur" != "$PA" ] || _fail "local commit did not advance cur"
refs_before=$(git -C "$PBARE" for-each-ref | wc -l)

if ( cd "$PWT" && "$JABC" post "ssh://localhost/$PREL" ) \
     >"$WORK/push.out" 2>"$WORK/push.err"; then
  _fail "ref-less host post unexpectedly succeeded: $(cat "$WORK/push.out")"
fi
grep -q "no remote branch selected" "$WORK/push.err" \
  || { echo "--- err ---"; cat "$WORK/push.err"; _fail "ref-less host post did not refuse 'no remote branch selected'"; }
after=$(git -C "$PBARE" rev-parse master)
[ "$after" = "$PA" ] || _fail "no-branch refusal still moved master ($PA -> $after)"
refs_after=$(git -C "$PBARE" for-each-ref | wc -l)
[ "$refs_after" = "$refs_before" ] || _fail "no-branch refusal created a ref on the peer"
git -C "$PBARE" fsck >/dev/null 2>&1 || _fail "bare fails fsck"
pass
