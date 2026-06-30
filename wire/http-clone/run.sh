#!/bin/sh
#  wire/http-clone — `jab get http://…` fresh-clones over the smart-HTTP curl
#  transport (GIT-012; no native `be` counterpart — be has no http: wire).  A
#  hermetic python3 server wraps `git upload-pack` (advert + --stateless-rpc);
#  asserts the recorded wtlog tip == HEAD and the tree matches `git clone`.
#  This case can ONLY pass via THIS worktree's shared/wire.js http path.
. "$(dirname "$0")/../lib/wirecase.sh"

wire_seed
wire_http_up "$BARE"
trap 'wire_http_down' EXIT INT TERM

mkdir "$WORK/jT"
( cd "$WORK/jT" && "$JABC" get "$HURL?/repo" ) \
  >"$WORK/jT.out" 2>"$WORK/jT.err" \
  || { echo "--- err ---"; cat "$WORK/jT.err"; _fail "http clone failed"; }

ct=$(wire_tip "$WORK/jT")
[ "$ct" = "$TIP_V2" ] || _fail "clone tip $ct != HEAD $TIP_V2"
wire_match "$WORK/jT"
pass
