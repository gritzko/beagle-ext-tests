#!/bin/sh
#  wire/ssh-incremental — clone @tags/v1.0, then update @tags/v2.0 over ssh:.
#  The tip must advance v1 -> v2 across the incremental fetch (haves from the
#  v1 closure already in the local store; only c2's new objects travel).
#  Mirrors C post/06-fetch-incremental (clone A, advance, re-fetch B).  Tag
#  pinning uses the `?tags/<x>` form (verified == native `be get`).  Needs
#  ssh-to-localhost (WITH_SSH).
. "$(dirname "$0")/../lib/wirecase.sh"

wire_seed
mkdir "$WORK/jT"
( cd "$WORK/jT" && "$JABC" get "ssh://localhost/$REL?tags/v1.0" ) \
  >"$WORK/c1.out" 2>"$WORK/c1.err" || { cat "$WORK/c1.err"; _fail "clone @v1.0 failed"; }
t1=$(wire_tip "$WORK/jT")
[ "$t1" = "$TIP_V1" ] || _fail "clone @v1.0 tip $t1 != $TIP_V1"
[ -f "$WORK/jT/b.txt" ] && _fail "v1.0 clone unexpectedly has b.txt (that is c2)"

( cd "$WORK/jT" && "$JABC" get "ssh://localhost/$REL?tags/v2.0" ) \
  >"$WORK/c2.out" 2>"$WORK/c2.err" || { cat "$WORK/c2.err"; _fail "update @v2.0 failed"; }
t2=$(wire_tip "$WORK/jT")
[ "$t2" = "$TIP_V2" ] || _fail "update @v2.0 tip $t2 != $TIP_V2"
wire_match "$WORK/jT"
pass
