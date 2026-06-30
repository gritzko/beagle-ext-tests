#!/bin/sh
#  wire/put-force-http — GIT-014: `jab put http://…?master` sets a remote ref to
#  cur's tip over the smart-HTTP receive-pack curl transport (force-write, no FF
#  gate).  Clone master@A (ssh, to build the be store), commit a FF descendant,
#  then `jab put` over http: the bare's master must move to cur + stay fsck-clean.
#  Needs ssh-to-localhost (clone) + python3/curl (WITH_SSH).
. "$(dirname "$0")/../lib/wirecase.sh"

wire_push_seed
wire_http_rp_up "$PBARE"
trap 'wire_http_rp_down' EXIT INT TERM

cur=$(wire_local_commit "$PWT" "$(printf 'A\nHTTPPUT\n')")
[ -n "$cur" ] && [ "$cur" != "$PA" ] || _fail "local commit did not advance cur"

( cd "$PWT" && "$JABC" put "$RURL/peer.git?master" ) \
  >"$WORK/put.out" 2>"$WORK/put.err" \
  || { echo "--- err ---"; cat "$WORK/put.err"; _fail "http force put failed"; }

after=$(git -C "$PBARE" rev-parse master)
[ "$after" = "$cur" ] || _fail "force put did not set bare master to cur ($cur; got $after)"
git -C "$PBARE" fsck >/dev/null 2>&1 || _fail "pushed bare fails fsck"
pass
