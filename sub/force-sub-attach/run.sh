#!/bin/sh
# test/sub/force-sub-attach — GET-047, [/wiki/GET] "Summary of invocation
# patterns" item 4.2: `get!` recurs FORCEFULLY into EVERY submodule — including
# one attached DIFFERENTLY (here DETACHED via `get ?<sha>` inside it) — and
# checks each out at the parent's pinned hash.  Observed re-attach shape,
# asserted below: the sub's `.be` anchor is REWRITTEN to redirect + the
# parent-owned track row `//…/vendor/sub#<pin>` (DIS-072 pin-URI) — the old
# detach record does not survive.
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
# 0. clone the parent; DETACH the mounted sub at its own current commit
#    (`get ?<sha>` = D2 detach -> a bare `#<sha>` record = attached DIFFERENTLY).
# ============================================================================
T1="$WORK/wt"
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { cat "$WORK/last.err"; _fail "clone exit $_rc"; }
[ "$(sc_subtip "$T1/vendor/sub")" = "$SUBTIP0" ] || _fail "clone: sub not at pin0"

( cd "$T1/vendor/sub" && "$JABC" get "?$SUBTIP0" ) >"$WORK/det.out" 2>&1 \
    || { cat "$WORK/det.out"; _fail "detach inside the sub"; }
grep -q "	get	#$SUBTIP0\$" "$T1/vendor/sub/.be" \
    || { cat "$T1/vendor/sub/.be"; _fail "sub not detached (no #<sha> record)"; }
# a sub-local dirty edit too — get! must discard it along with the detachment.
printf 'sub payload DIRTY\n' > "$T1/vendor/sub/lib.c"

# ============================================================================
# 1. UPSTREAM advance: new sub commit; parent file edit post, then the absorb
#    post bumps the gitlink to SUBTIP1 (postSubs; the bump post is selective).
# ============================================================================
( cd "$SUBSTORE" && printf 'sub payload v2\n' > lib.c && "$JABC" post '#sub v2' ) \
    >"$WORK/s2.out" 2>&1 || { cat "$WORK/s2.out"; _fail "sub upstream post"; }
SUBTIP1=$(sc_tip "$SUBSTORE"); sc_is40 "$SUBTIP1" "sub tip1"
( cd "$PARSTORE" && printf 'int main(void){return 1;}\n' > main.c \
    && "$JABC" post '#parent v2' ) \
    >"$WORK/pv2.out" 2>&1 || { cat "$WORK/pv2.out"; _fail "parent v2 post"; }
( cd "$PARSTORE/vendor/sub" && "$JABC" get "file://$SUBSTORE/.be#$SUBTIP1" ) \
    >"$WORK/sadv.out" 2>&1 || { cat "$WORK/sadv.out"; _fail "advance parent's sub mount"; }
( cd "$PARSTORE" && "$JABC" post '#absorb sub v2' ) \
    >"$WORK/padv.out" 2>&1 || { cat "$WORK/padv.out"; _fail "parent absorb post"; }
PARTIP1=$(sc_tip "$PARSTORE"); sc_is40 "$PARTIP1" "par tip1"
[ "$(sc_gitlink_pin "$PARSTORE" "$SUBPATH")" = "$SUBTIP1" ] \
    || _fail "upstream gitlink not bumped to SUBTIP1"

# ============================================================================
# 2. FORCE update `get!`: the parent updates AND the differently-attached sub
#    is FORCED back onto the parent's pin — checkout at SUBTIP1, dirty edit
#    discarded, anchor re-attached to the `//…/sub#pin` track row.
# ============================================================================
_rc=0
( cd "$T1" && "$JABC" get! "file://$PARSTORE/.be#$PARTIP1" ) \
    >"$WORK/g.out" 2>"$WORK/g.err" || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/g.err"; _fail "get! exit $_rc"; }

grep -q 'return 1' "$T1/main.c" || _fail "get!: parent main.c not updated"
[ "$(sc_gitlink_pin "$T1" "$SUBPATH")" = "$SUBTIP1" ] \
    || _fail "get!: new gitlink row did not land in the parent baseline"
_got=$(cat "$T1/vendor/sub/lib.c")
[ "$_got" = "sub payload v2" ] \
    || _fail "get!: sub lib.c [$_got] != pinned v2 (dirty/detached state survived)"
[ "$(sc_subtip "$T1/vendor/sub")" = "$SUBTIP1" ] \
    || _fail "get!: mounted sub tip != SUBTIP1 (not forced onto the pin)"
ROW=$(_lastget "$T1/vendor/sub")
[ "$ROW" = "A=// P=/vendor/sub F=$SUBTIP1" ] \
    || _fail "get!: sub not re-attached to the parent pin row (got: $ROW)"
grep -q "	get	#" "$T1/vendor/sub/.be" \
    && _fail "get!: the old detach record survived the re-attach"
echo "ok   get! forced the detached sub onto the pin + re-attached ($ROW)"

pass
