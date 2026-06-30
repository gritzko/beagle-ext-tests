#!/bin/sh
#  wire/ssh-clone — `jab get ssh://localhost/<rel>` fresh-clones a vanilla git
#  repo over the JS upload-pack client (git-upload-pack over ssh).  Asserts the
#  recorded wtlog tip == the bare repo's master/HEAD and the checked-out tree
#  matches a reference `git clone`.  Mirrors C get/26-cached-no-wire's clone
#  leg + post/06-fetch-incremental's seed.  Needs ssh-to-localhost (WITH_SSH).
. "$(dirname "$0")/../lib/wirecase.sh"

wire_seed
mkdir "$WORK/jT"
( cd "$WORK/jT" && "$JABC" get "ssh://localhost/$REL" ) \
  >"$WORK/jT.out" 2>"$WORK/jT.err" \
  || { echo "--- err ---"; cat "$WORK/jT.err"; _fail "ssh clone failed"; }

ct=$(wire_tip "$WORK/jT")
[ "$ct" = "$TIP_V2" ] || _fail "clone tip $ct != HEAD $TIP_V2"
wire_match "$WORK/jT"
pass
