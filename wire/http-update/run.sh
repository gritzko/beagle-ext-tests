#!/bin/sh
#  wire/http-update — clone over http:, then re-`jab get` the same tip (no-op
#  update) over the smart-HTTP curl transport.  Tip must stay == HEAD with the
#  worktree unchanged.  GIT-012-only path (be has no http: wire).
. "$(dirname "$0")/../lib/wirecase.sh"

wire_seed
wire_http_up "$BARE"
trap 'wire_http_down' EXIT INT TERM

mkdir "$WORK/jT"
( cd "$WORK/jT" && "$JABC" get "$HURL?/repo" ) >"$WORK/jT.out" 2>"$WORK/jT.err" \
  || { cat "$WORK/jT.err"; _fail "http clone failed"; }
t1=$(wire_tip "$WORK/jT")
[ "$t1" = "$TIP_V2" ] || _fail "clone tip $t1 != HEAD $TIP_V2"

( cd "$WORK/jT" && "$JABC" get "$HURL?/repo" ) >"$WORK/jT2.out" 2>"$WORK/jT2.err" \
  || { cat "$WORK/jT2.err"; _fail "http no-op update failed"; }
t2=$(wire_tip "$WORK/jT")
[ "$t2" = "$TIP_V2" ] || _fail "update tip $t2 != HEAD $TIP_V2"
wire_match "$WORK/jT"
pass
