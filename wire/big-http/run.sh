#!/bin/sh
#  wire/big-http (LABEL: big) — TREADMILL: `jab get http://…` clones the real
#  git source tree (src/git, ~290 MB pack) over the smart-HTTP curl transport
#  (GIT-012), then re-gets it (no-op update).  Asserts the recorded wtlog tip
#  == the bare's HEAD.  This is the http: counterpart to the C clone-git
#  treadmill — and the ONLY way to exercise the big-repo http path, which has
#  no native `be` equivalent.  Slow/large, hence the `big` ctest label.  Needs
#  git + python3 + curl; SKIPs cleanly if src/git absent.
. "$(dirname "$0")/../lib/wirecase.sh"

wire_big_mirror "${GIT_TREADMILL_SRC:-/home/gritzko/src/git}"

wire_http_up "$BARE"
trap 'wire_http_down' EXIT INT TERM

mkdir "$WORK/jT"
( cd "$WORK/jT" && "$JABC" get "$HURL?/git" ) \
  >"$WORK/jT.out" 2>"$WORK/jT.err" \
  || { echo "--- err (tail) ---"; tail -20 "$WORK/jT.err"; _fail "big http clone failed"; }
t1=$(wire_tip "$WORK/jT")
[ "$t1" = "$WANT" ] || _fail "big http clone tip $t1 != HEAD $WANT"

( cd "$WORK/jT" && "$JABC" get "$HURL?/git" ) \
  >"$WORK/jT2.out" 2>"$WORK/jT2.err" || { tail -20 "$WORK/jT2.err"; _fail "big http update failed"; }
t2=$(wire_tip "$WORK/jT")
[ "$t2" = "$WANT" ] || _fail "big http update tip $t2 != HEAD $WANT"
echo "BIG-HTTP tip=$t1 == HEAD"
pass
