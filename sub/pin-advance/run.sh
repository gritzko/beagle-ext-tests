#!/bin/sh
# test/sub/pin-advance — GET-047, [/wiki/GET] "Summary of invocation patterns"
# item 4.1: a sub ATTACHED TO THE PARENT'S PIN follows a pin ADVANCE at UPDATE
# time (a re-get over an existing clone — clone-time follow is sub/cycle).  The
# parent takes the new commit, the mounted sub checks out the NEW pin, and the
# sub's track row re-pins to the new `#<pin>` (DIS-072 pin-URI, parent-owned).
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent

# _lastget SUBWT — the recentmost `get` row of a sub wtlog as `A=.. P=.. F=..`
# (the pinref probe; the pin row the PARENT owns per DIS-072).
cat > "$WORK/.lastget.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
let last;
for(const r of wtlog.open(info).rows) if(r.verb==="get") last=r;
let s;
if(!last) s="NOROW";
else s="A="+(last.uri.authority==null?"":last.uri.authority)
       +" P="+(last.uri.path||"")+" F="+(last.uri.fragment||"");
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w(s);
EOF
_lastget() { "$JABC" "$WORK/.lastget.js" "$1" "$BEDIR" 2>/dev/null; }

# ============================================================================
# 0. clone the parent at PARTIP0: the sub mounts ATTACHED to pin SUBTIP0.
# ============================================================================
T1="$WORK/wt"
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { cat "$WORK/last.err"; _fail "clone exit $_rc"; }
[ "$(sc_subtip "$T1/vendor/sub")" = "$SUBTIP0" ] || _fail "clone: sub not at pin0"

# ============================================================================
# 1. UPSTREAM advance (all inside the fixture): a new sub commit, then the
#    parent absorbs it — mounted sub re-gets the new tip (classifies `adv`),
#    a parent file edit, and a parent post that bumps the gitlink (pinref §2).
# ============================================================================
( cd "$SUBSTORE" && printf 'sub payload v2\n' > lib.c && "$JABC" post '#sub v2' ) \
    >"$WORK/s2.out" 2>&1 || { cat "$WORK/s2.out"; _fail "sub upstream post"; }
SUBTIP1=$(sc_tip "$SUBSTORE"); sc_is40 "$SUBTIP1" "sub tip1"
[ "$SUBTIP1" != "$SUBTIP0" ] || _fail "sub upstream tip did not advance"

# parent file edit rides its OWN commit-all post (the absorb post below is
# SELECTIVE — postSubs' gitlink-bump `put` row makes it so).
( cd "$PARSTORE" && printf 'int main(void){return 1;}\n' > main.c \
    && "$JABC" post '#parent v2' ) \
    >"$WORK/pv2.out" 2>&1 || { cat "$WORK/pv2.out"; _fail "parent v2 post"; }
( cd "$PARSTORE/vendor/sub" && "$JABC" get "file://$SUBSTORE/.be#$SUBTIP1" ) \
    >"$WORK/sadv.out" 2>&1 || { cat "$WORK/sadv.out"; _fail "advance parent's sub mount"; }
( cd "$PARSTORE" && "$JABC" post '#absorb sub v2' ) \
    >"$WORK/padv.out" 2>&1 || { cat "$WORK/padv.out"; _fail "parent absorb post"; }
PARTIP1=$(sc_tip "$PARSTORE"); sc_is40 "$PARTIP1" "par tip1"
[ "$PARTIP1" != "$PARTIP0" ] || _fail "parent upstream tip did not advance"
[ "$(sc_gitlink_pin "$PARSTORE" "$SUBPATH")" = "$SUBTIP1" ] \
    || _fail "upstream gitlink not bumped to SUBTIP1"

# ============================================================================
# 2. UPDATE get in the clone (explicit remote#tip — the update-test spelling;
#    DIS-076: a bare post mints no ref, so the remote is pinned).  The parent
#    files update AND the attached sub follows to the NEW pin.
# ============================================================================
_rc=0
( cd "$T1" && "$JABC" get "file://$PARSTORE/.be#$PARTIP1" ) \
    >"$WORK/g.out" 2>"$WORK/g.err" || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/g.err"; _fail "update get exit $_rc"; }

grep -q 'return 1' "$T1/main.c" || _fail "parent main.c not updated to v2"
[ "$(sc_gitlink_pin "$T1" "$SUBPATH")" = "$SUBTIP1" ] \
    || _fail "clone gitlink pin != SUBTIP1 after update get"
_got=$(cat "$T1/vendor/sub/lib.c")
[ "$_got" = "sub payload v2" ] || _fail "sub lib.c [$_got] != v2 (sub did not follow the pin)"
[ "$(sc_subtip "$T1/vendor/sub")" = "$SUBTIP1" ] \
    || _fail "mounted sub tip != SUBTIP1 (checkout did not follow the pin advance)"
ROW=$(_lastget "$T1/vendor/sub")
case "$ROW" in
    *"F=$SUBTIP1") ;;
    *) _fail "sub track row not re-pinned to #SUBTIP1 (got: $ROW)" ;;
esac
echo "ok   attached sub followed the pin advance on update get ($ROW)"

pass
