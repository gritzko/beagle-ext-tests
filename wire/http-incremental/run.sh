#!/bin/sh
#  wire/http-incremental — clone @tags/v1.0, then update @tags/v2.0 over the
#  smart-HTTP curl transport.  Tip advances v1 -> v2 (incremental: the v1
#  closure already cached; v2's want POSTed with v1 haves).  GIT-012-only path
#  (be has no http: wire).  Mirrors the ssh-incremental scenario.
. "$(dirname "$0")/../lib/wirecase.sh"

wire_seed
wire_http_up "$BARE"
trap 'wire_http_down' EXIT INT TERM

mkdir "$WORK/jT"
( cd "$WORK/jT" && "$JABC" get "$HURL?tags/v1.0" ) \
  >"$WORK/c1.out" 2>"$WORK/c1.err" || { cat "$WORK/c1.err"; _fail "clone @v1.0 failed"; }
t1=$(wire_tip "$WORK/jT")
[ "$t1" = "$TIP_V1" ] || _fail "clone @v1.0 tip $t1 != $TIP_V1"
[ -f "$WORK/jT/b.txt" ] && _fail "v1.0 clone unexpectedly has b.txt (that is c2)"

( cd "$WORK/jT" && "$JABC" get "$HURL?tags/v2.0" ) \
  >"$WORK/c2.out" 2>"$WORK/c2.err" || { cat "$WORK/c2.err"; _fail "update @v2.0 failed"; }
t2=$(wire_tip "$WORK/jT")
[ "$t2" = "$TIP_V2" ] || _fail "update @v2.0 tip $t2 != $TIP_V2"
wire_match "$WORK/jT"
pass
