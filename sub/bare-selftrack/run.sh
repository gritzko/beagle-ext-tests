#!/bin/sh
# test/sub/bare-selftrack — POST-026 BUG: a bare `post` inside a CLEAN mounted
# SUBMODULE that is AHEAD of its base must take the DIS-074 track-advance arm
# (FF the sub's OWN tracked branch/trunk to cur's tip), NOT the `//WT` wt-target
# SELF-post arm.
#
# A mounted sub's DIS-072 re-attach records its track as the PARENT-MOUNT address
# `//<wt>/<subpath>` (submount.trackUri).  That address resolves — via the SAME
# discover.wtdir/treeAt routines advanceWorktree uses — to the sub's OWN on-disk
# dir.  So the bare-post track-advance (advanceTrack) picked the advanceWorktree
# sub-arm, which then refused `POSTNONE: //<wt>/<subpath> is this worktree` — a
# clean-but-ahead sub could never bare-advance.
#
# RED before the fix: `(cd T1/vendor/sub && jab post)` throws the self POSTNONE
# and the tracked branch (trunk) stays STALE.  GREEN after: advanceTrack detects
# the self wt-target and falls through to advanceBranch — trunk FFs to cur's tip
# (worktree.mkd:53-54), no new commit, the sub's own cur untouched.
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent

T1="$WORK/get1"
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { echo "--- get1 err ---"; cat "$WORK/last.err"; _fail "get1 exit $_rc"; }
[ -f "$T1/vendor/sub/lib.c" ] || _fail "get1: sub not mounted/checked out"

SUBWT="$T1/vendor/sub"

# Sanity: the mounted sub's recentmost `get` track is a scheme-less `//…`
# wt-target (the DIS-072 parent-mount address) — the SELF-reference this repro
# rides.  A `file:`/`?` track would exercise a different arm.
cat > "$WORK/.track.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);const wtl=wtlog.open(info);
let last="";
for(const r of wtl.rows){ if(r.verb!=="get") continue;
  const ref=wtlog.refOf(r.uri,r.local); if(!ref.sha && !ref.branch) continue;
  last=(r.uri&&r.uri.scheme===undefined&&r.uri.authority!==undefined)?"WT":"OTHER"; }
function w(s){const u=utf8.Encode(s+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w(last);
EOF
TRACK=$("$JABC" "$WORK/.track.js" "$SUBWT" "$BEDIR" 2>/dev/null)
[ "$TRACK" = "WT" ] || _fail "fixture: sub track is not a // wt-target (got '$TRACK')"

# trunk ref probe over the sub's store (a secondary wt: its shard is the PARENT
# store); resolution stays in shared/store.js resolveRef.
cat > "$WORK/.ref.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const info=be.treeAt(process.argv[2]);
const k=store.open(info.storePath,info.project);
const t=k.resolveRef(process.argv[4]||"")||"";
const u=utf8.Encode(t+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
_subref() { "$JABC" "$WORK/.ref.js" "$1" "$BEDIR" "$2" 2>/dev/null; }

# --- commit AHEAD in the sub: the sub's cur descends its tracked branch tip ---
( cd "$SUBWT" && printf 'sub payload v2 AHEAD\n' > lib.c \
    && "$JABC" put lib.c && "$JABC" post '#sub ahead' ) >/dev/null 2>&1 \
    || _fail "sub: post ahead failed"
SUBTIP=$(sc_subtip "$SUBWT"); sc_is40 "$SUBTIP" "sub tip (ahead)"
TRUNK0=$(_subref "$SUBWT" "")
[ "$TRUNK0" != "$SUBTIP" ] || _fail "fixture: sub trunk already at cur (trunk=$TRUNK0 cur=$SUBTIP)"

# --- the op under test: a BARE post INSIDE the clean-but-ahead sub -----------
RC=0
( cd "$SUBWT" && "$JABC" post ) >"$WORK/bp.out" 2>"$WORK/bp.err" || RC=$?

if grep -q "is this worktree" "$WORK/bp.err"; then
    echo "--- bp.err ---"; cat "$WORK/bp.err"
    _fail "bare post inside the sub hit the wt-target SELF arm (POSTNONE is this worktree)"
fi
TRUNK1=$(_subref "$SUBWT" "")
if [ "$RC" -ne 0 ] || [ "$TRUNK1" != "$SUBTIP" ]; then
    echo "--- bp.err ---"; cat "$WORK/bp.err"
    echo "--- bp.out ---"; cat "$WORK/bp.out"
    echo "  trunk before=$TRUNK0 after=$TRUNK1 want=$SUBTIP" >&2
    _fail "bare post inside the sub did not FF the tracked branch (see above)"
fi

# The sub's own cur is UNTOUCHED (a bare advance makes no commit, no retie).
[ "$(sc_subtip "$SUBWT")" = "$SUBTIP" ] \
    || _fail "bare post inside the sub moved the sub's own cur (must stay $SUBTIP)"

echo "ok   bare post inside the clean-but-ahead sub FF-advanced trunk (no self POSTNONE)"
pass
