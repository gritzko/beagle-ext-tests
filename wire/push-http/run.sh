#!/bin/sh
#  wire/push-http — GIT-013: `jab post http://…?master` FF-pushes cur's tip onto
#  a LOCAL bare over the smart-HTTP receive-pack curl transport (a hermetic
#  python3 backend shelling `git receive-pack --stateless-rpc`).  The be store is
#  built by an ssh clone (no http upload-pack here); the PUSH then rides http.
#  Asserts the bare's master advances to cur + stays fsck-clean.  Needs
#  ssh-to-localhost (for the clone) + python3/curl (WITH_SSH).
. "$(dirname "$0")/../lib/wirecase.sh"

wire_push_seed
wire_http_rp_up "$PBARE"
trap 'wire_http_rp_down' EXIT INT TERM

cur=$(wire_local_commit "$PWT" "$(printf 'A\nHTTP\n')")
[ -n "$cur" ] && [ "$cur" != "$PA" ] || _fail "local commit did not advance cur"

( cd "$PWT" && "$JABC" post "$RURL/peer.git?master" ) \
  >"$WORK/push.out" 2>"$WORK/push.err" \
  || { echo "--- err ---"; cat "$WORK/push.err"; _fail "http FF push failed"; }

after=$(git -C "$PBARE" rev-parse master)
[ "$after" = "$cur" ] || _fail "bare master did not FF-advance to cur ($cur; got $after)"
git -C "$PBARE" fsck >/dev/null 2>&1 || _fail "pushed bare fails fsck"
pass
