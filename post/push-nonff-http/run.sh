#!/bin/sh
#  post/push-nonff-http — POST-027 cell 5-v over http: wire/push-nonff's
#  divergence fixture, ridden over the smart-HTTP receive-pack transport
#  (hermetic python3 backend shelling `git receive-pack --stateless-rpc`, the
#  wire/push-http shape).  Clone master@A, commit C locally, advance the peer
#  to B — `jab post http://…?master` must refuse POSTNOFF on the stateless
#  http arm of pushRemote (verbs/post/post.js:424-499) and leave the bare's
#  master UNCHANGED.  Spec: /wiki/POST.mkd §"Summary of invocation patterns"
#  row 5.  Needs ssh-to-localhost (for the clone) + python3/curl (WITH_SSH).
. "$(dirname "$0")/../../wire/lib/wirecase.sh"

wire_push_seed
wire_http_rp_up "$PBARE"
trap 'wire_http_rp_down' EXIT INT TERM

cur=$(wire_local_commit "$PWT" "$(printf 'A\nC\n')")     # client tip C (parent A)
[ -n "$cur" ] && [ "$cur" != "$PA" ] || _fail "local commit did not advance cur"
B=$(wire_peer_advance "$PBARE")                          # peer master -> B
[ "$B" != "$PA" ] && [ "$B" != "$cur" ] || _fail "peer did not advance to a divergent B"

if ( cd "$PWT" && "$JABC" post "$RURL/peer.git?master" ) \
     >"$WORK/push.out" 2>"$WORK/push.err"; then
  _fail "non-FF http post unexpectedly succeeded: $(cat "$WORK/push.out")"
fi
grep -q "can not be fast-forwarded" "$WORK/push.err" \
  || { echo "--- err ---"; cat "$WORK/push.err"; _fail "non-FF http post did not refuse via the non-FF report"; }
after=$(git -C "$PBARE" rev-parse master)
[ "$after" = "$B" ] || _fail "refused non-FF http post still moved the bare ($B -> $after)"
git -C "$PBARE" fsck >/dev/null 2>&1 || _fail "bare fails fsck"
pass
