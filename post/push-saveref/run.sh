#!/bin/sh
#  post/push-saveref — POST-027 matrix row "5 e2e push asserts the saved
#  remote-tracking row (ingest.saveRemoteRef is unit-tested only,
#  wire/saveremote)".  After a SUCCESSFUL FF push over ssh, pushRemote
#  (verbs/post/post.js:424-499) records the just-advanced remote tip as a
#  remote-tracking refs row (ingest.saveRemoteRef) in the LOCAL store — the
#  sibling probe.js reads it back via store.eachRemote (the wire/saveremote
#  probe, here end-to-end).  Spec: /wiki/POST.mkd §"Summary of invocation
#  patterns" row 5.  Needs ssh-to-localhost (WITH_SSH).
. "$(dirname "$0")/../../wire/lib/wirecase.sh"

wire_push_seed
cur=$(wire_local_commit "$PWT" "$(printf 'A\nSAVE\n')")
[ -n "$cur" ] && [ "$cur" != "$PA" ] || _fail "local commit did not advance cur"

( cd "$PWT" && "$JABC" post "ssh://localhost/$PREL?master" ) \
  >"$WORK/push.out" 2>"$WORK/push.err" \
  || { echo "--- err ---"; cat "$WORK/push.err"; _fail "ssh FF push failed"; }
after=$(git -C "$PBARE" rev-parse master)
[ "$after" = "$cur" ] || _fail "bare master did not FF-advance to cur ($cur; got $after)"

#  The e2e assertion: the LOCAL store now carries a remote-tracking row for
#  localhost at the pushed tip.  ABSOLUTE script path so jab treats probe.js
#  as a file (the wire/saveremote invocation shape).
PROBE_WT="$PWT" PROBE_TIP="$cur" "$JABC" "$_CASE/probe.js" \
  >"$WORK/probe.out" 2>"$WORK/probe.err" \
  || { echo "--- probe ---"; cat "$WORK/probe.out" "$WORK/probe.err"; \
       _fail "no remote-tracking row for the pushed tip in the local store"; }
pass
