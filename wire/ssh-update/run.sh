#!/bin/sh
#  wire/ssh-update — clone over ssh:, then re-`jab get` the SAME tip (no-op
#  update).  The second fetch must converge to the identical tip with the
#  worktree unchanged (haves negotiated, nothing new to apply).  Needs
#  ssh-to-localhost (WITH_SSH).
. "$(dirname "$0")/../lib/wirecase.sh"

wire_seed
mkdir "$WORK/jT"
( cd "$WORK/jT" && "$JABC" get "ssh://localhost/$REL" ) >"$WORK/jT.out" 2>"$WORK/jT.err" \
  || { cat "$WORK/jT.err"; _fail "ssh clone failed"; }
t1=$(wire_tip "$WORK/jT")
[ "$t1" = "$TIP_V2" ] || _fail "clone tip $t1 != HEAD $TIP_V2"

( cd "$WORK/jT" && "$JABC" get "ssh://localhost/$REL" ) >"$WORK/jT2.out" 2>"$WORK/jT2.err" \
  || { cat "$WORK/jT2.err"; _fail "ssh no-op update failed"; }
t2=$(wire_tip "$WORK/jT")
[ "$t2" = "$TIP_V2" ] || _fail "update tip $t2 != HEAD $TIP_V2"
wire_match "$WORK/jT"
pass
