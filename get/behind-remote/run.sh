#!/bin/sh
#  test/get/behind-remote — GET-047: HISTORY BEHIND (3.2) × a REMOTE re-get
#  (1.6): after a clone at ?tags/v2.0, a re-get of the OLDER ?tags/v1.0 walks
#  the wt BACK cleanly — the v2-only b.txt goes, a.txt returns to A, and the
#  recorded tip is v1's sha.  Needs git + ssh-to-localhost; SKIPs otherwise.
. "$(dirname "$0")/../../wire/lib/wirecase.sh"

# BE_TEST_NO_SSH=1 force-skips ssh cases (CI); see wire/lib/wirecase.sh.
[ -z "${BE_TEST_NO_SSH:-}" ] || { echo "SKIP [$NAME] BE_TEST_NO_SSH set"; exit 0; }
command -v ssh >/dev/null 2>&1 || { echo "SKIP [$NAME] no ssh"; exit 0; }
ssh -o BatchMode=yes -o ConnectTimeout=4 localhost true >/dev/null 2>&1 \
  || { echo "SKIP [$NAME] no passwordless ssh to localhost"; exit 0; }

wire_seed
mkdir "$WORK/jT"
( cd "$WORK/jT" && "$JABC" get "ssh://localhost/$REL?tags/v2.0" ) \
    >"$WORK/jT.out" 2>"$WORK/jT.err" \
  || { cat "$WORK/jT.err"; _fail "ssh clone @v2.0 failed"; }
t1=$(wire_tip "$WORK/jT")
[ "$t1" = "$TIP_V2" ] || _fail "clone tip $t1 != v2.0 $TIP_V2"
[ -e "$WORK/jT/b.txt" ] || _fail "clone @v2.0 missing b.txt"

#  The walk BACK: re-get the OLDER tag over the same wire.
( cd "$WORK/jT" && "$JABC" get "ssh://localhost/$REL?tags/v1.0" ) \
    >"$WORK/jT2.out" 2>"$WORK/jT2.err" \
  || { cat "$WORK/jT2.err"; _fail "re-get @v1.0 (walk back) failed"; }
t2=$(wire_tip "$WORK/jT")
[ "$t2" = "$TIP_V1" ] || _fail "walk-back tip $t2 != v1.0 $TIP_V1"
[ "$(cat "$WORK/jT/a.txt")" = "A" ] || _fail "a.txt not walked back to A"
[ ! -e "$WORK/jT/b.txt" ] || _fail "walk-back left b.txt (a v2.0-only file)"
[ "$(cat "$WORK/jT/d/c.txt")" = "C" ] || _fail "d/c.txt lost on walk-back"

pass
