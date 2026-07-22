#!/bin/sh
#  wire/big-ssh (LABEL: big) — TREADMILL: `jab get ssh://…` clones the real
#  git source tree (src/git, ~290 MB pack) over the JS upload-pack client, then
#  re-gets it (no-op update).  Asserts the recorded wtlog tip == the bare's
#  HEAD.  Mirrors the C clone-git treadmill; slow/large, hence the `big` ctest
#  label so it can be selected/excluded.  ssh peer resolves HOME-relative, so
#  the bare must sit under $HOME — we build a tiny bare MIRROR of src/git's
#  HEAD there (clone --mirror --depth 1) to keep the fixture self-contained and
#  hermetic.  Needs git + ssh-to-localhost; SKIPs cleanly if src/git absent.
. "$(dirname "$0")/../lib/wirecase.sh"

wire_need_ssh
wire_big_mirror "${GIT_TREADMILL_SRC:-/home/gritzko/src/git}"

mkdir "$WORK/jT"
( cd "$WORK/jT" && "$JABC" get "ssh://localhost/$REL" ) \
  >"$WORK/jT.out" 2>"$WORK/jT.err" \
  || { echo "--- err (tail) ---"; tail -20 "$WORK/jT.err"; _fail "big ssh clone failed"; }
t1=$(wire_tip "$WORK/jT")
[ "$t1" = "$WANT" ] || _fail "big ssh clone tip $t1 != HEAD $WANT"

( cd "$WORK/jT" && "$JABC" get "ssh://localhost/$REL" ) \
  >"$WORK/jT2.out" 2>"$WORK/jT2.err" || { tail -20 "$WORK/jT2.err"; _fail "big ssh update failed"; }
t2=$(wire_tip "$WORK/jT")
[ "$t2" = "$WANT" ] || _fail "big ssh update tip $t2 != HEAD $WANT"
echo "BIG-SSH tip=$t1 == HEAD"
pass
