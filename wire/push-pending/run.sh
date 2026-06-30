#!/bin/sh
#  wire/push-pending — PENDING placeholder for push (post/put) OVER THE WIRE.
#  GIT-012 landed FETCH only: shared/wire.js exports `fetch` (want/have/done)
#  and has NO `receive-pack`/`send-pack`, so `be post ssh://…` / `be post
#  http://…` (wire push) is UNIMPLEMENTED and OUT OF SCOPE for this ticket.
#
#  The LOCAL commit round-trip (jab put / jab post into the local store, then
#  verify) is already covered by test/post/* and test/parity/{post,put}; no
#  wire is involved there, so nothing is added by duplicating it here.  This
#  case is registered as a known-skip so the wire-push scenario is visible in
#  the suite and flips to a real test when the receive-pack client lands.
NAME=push-pending
echo "SKIP [$NAME] wire push (receive-pack) unimplemented — GIT-012 is fetch-only; see shared/wire.js"
exit 0
