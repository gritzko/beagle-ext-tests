#!/bin/sh
#  post/push-eq — POST-027 cell 5-ii: remote already at cur's tip.  Clone the
#  peer (master@A), commit NOTHING, `jab post ssh://…?master` — the advert's
#  old sha equals cur, so pushRemote's eq arm (verbs/post/post.js:451-454)
#  refuses POSTNONE "already at" BEFORE any pack is built or sent.  Spec:
#  /wiki/POST.mkd §"Summary of invocation patterns" row 5 (every tip motion is
#  a FF; at-tip is a no-op refusal, mirrors row 1's POSTNONE).  The peer must
#  stay byte-identical.  Needs ssh-to-localhost (WITH_SSH).
. "$(dirname "$0")/../../wire/lib/wirecase.sh"

wire_push_seed
cur=$(wire_tip "$PWT")
[ "$cur" = "$PA" ] || _fail "clone tip is not the peer's master ($PA; got '$cur')"
cp -a "$PBARE" "$WORK/peer.before"

if ( cd "$PWT" && "$JABC" post "ssh://localhost/$PREL?master" ) \
     >"$WORK/push.out" 2>"$WORK/push.err"; then
  _fail "at-tip post unexpectedly succeeded: $(cat "$WORK/push.out")"
fi
grep -q "already at cur's tip" "$WORK/push.err" \
  || { echo "--- err ---"; cat "$WORK/push.err"; _fail "refusal is not the 'already at' report"; }
after=$(git -C "$PBARE" rev-parse master)
[ "$after" = "$PA" ] || _fail "at-tip refusal still moved the bare ($PA -> $after)"
diff -r "$WORK/peer.before" "$PBARE" >/dev/null 2>&1 \
  || _fail "peer is not byte-identical after the POSTNONE refusal (a pack was sent?)"
pass
