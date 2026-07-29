#!/bin/sh
# test/post/sub-dirty-parent — POST-034: a COMMIT-ALL post over a dirty
# MOUNTED sub must commit the parent's OWN dirty files too.
# Spec: /wiki/POST.mkd §"Summary of invocation patterns" row 2:
# "commit-all mode: nothing staged anywhere => auto-stage all changes, dirty
# subs bottom-up, the parent last".
#
# RED before the fix: `postSubs` records the sub's advance by appending a real
# `put <sub>#<newtip>` row to the PARENT wtlog (post.js:740); `postOne` then
# re-opens that wtlog and `fold-decide.decide` re-derives `anyPd` from it
# (fold-decide.js:107), reads "something is staged" and flips the whole parent
# commit to SELECTIVE — every dirty tracked parent file takes the
# `if (anyPd) keep(...)` baseline arm (fold-decide.js:158) and its change is
# silently left out of the commit.  The post still reports success.
#
# Leg 1 (the bug): parent TOP.c dirty + sub DOG.c dirty, NOTHING staged, bare
#   `post '#msg'` from the parent root => BOTH changes in the ONE parent commit.
# Leg 2 (the other direction): a GENUINELY selective post (a real user `put`
#   of one parent file + a real `put` inside the sub, so the sub commits and
#   the gitlink bump row is written) still commits EXACTLY the staged set —
#   a second dirty-but-unstaged parent file stays out.
. "$(dirname "$0")/../../lib/postcase.sh"

# _subtip WT — a wt's cur tip (works through the sub's `.be` FILE redirect).
_subtip() {
    cat > "$WORK/.subtip.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
const c=wtlog.open(info).curTip();
const u=utf8.Encode(((c&&c.sha)||"")+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.subtip.js" "$1" "$BEDIR" 2>/dev/null
}

# _blobat WT PATH — the COMMITTED content of PATH at the wt's cur tip (the
# oracle: what the commit actually carries, not what the wt file says).
_blobat() {
    cat > "$WORK/.blob.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
const k=store.open(info.storePath,info.project);
const c=wtlog.open(info).curTip();
let out="";
if(c&&c.sha){const tt=k.commitTree(c.sha);
  if(tt)k.readTreeRecursive(tt,function(l){
    if(l.path===process.argv[4]){const o=k.getObject(l.sha);if(o)out=utf8.Decode(o.bytes);}});}
const u=utf8.Encode(out);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.blob.js" "$1" "$BEDIR" "$2" 2>/dev/null
}

# _pinrow SUBPATH WTLOG SHA — seed a `put <subpath>#<sha>` gitlink row (the
# sub/nestedpost recipe: no CLI spelling for the first gitlink pin).
_pinrow() {
    cat > "$WORK/.pinrow.js" <<'EOF'
const ulog = require(process.argv[2] + "/shared/ulog.js");
ulog.append(process.argv[4], [{ verb: "put",
  uri: URI.make(undefined, undefined, process.argv[3], undefined, process.argv[5]) }]);
EOF
    "$JABC" "$WORK/.pinrow.js" "$BEDIR" "$1" "$2" "$3" >/dev/null 2>&1 || true
}

_is40() {
    case "$1" in
        ????????????????????????????????????????) ;;
        *) _fail "$2: not 40-hex: '$1'" ;;
    esac
}

# _mount PARENT SUBNAME — fixture: a parent wt with SUBNAME mounted+gitlinked.
_mount() {
    _p=$1; _s=$2
    mkdir -p "$_p/$_s"
    ( cd "$_p/$_s" && "$BE" get "file://$DOGSRC/.be#$DOGTIP0" ) >"$WORK/get.out" 2>&1 \
        || { cat "$WORK/get.out"; _fail "mount $_s"; }
    [ -f "$_p/$_s/.be" ] || _fail "$_p/$_s/.be not a FILE redirect (not mounted)"
    _pinrow "$_s" "$_p/.be/wtlog" "$DOGTIP0"
    ( cd "$_p" && "$BE" post '#mount sub' ) >"$WORK/mount.out" 2>&1 \
        || { cat "$WORK/mount.out"; _fail "commit $_s gitlink"; }
}

# --- the shared sub source store --------------------------------------------
DOGSRC="$WORK/dogsrc"; mkdir -p "$DOGSRC/.be"
( cd "$DOGSRC" && printf 'dog payload v1\n' > DOG.c && "$BE" post '#dog initial' ) \
    >/dev/null 2>&1 || _fail "dog source store setup"
DOGTIP0=$(_subtip "$DOGSRC"); _is40 "$DOGTIP0" "dog tip0"

# ===== Leg 1: COMMIT-ALL — the parent's own dirty file must land =============
P="$WORK/P"; mkdir -p "$P/.be"
( cd "$P" && printf 'top payload v1\n' > TOP.c && "$BE" post '#parent initial' ) \
    >/dev/null 2>&1 || _fail "parent P setup"
_mount "$P" dog
TOP0=$(_subtip "$P"); _is40 "$TOP0" "P tip0"

# dirty BOTH sides, stage NOTHING (the commit-all shape).
printf 'top payload v2 EDITED\n' > "$P/TOP.c"
printf 'dog payload v2 EDITED\n' > "$P/dog/DOG.c"

RC=0
( cd "$P" && "$JABC" post '#POST-034: commit all' ) \
    >"$WORK/post.out" 2>"$WORK/post.err" || RC=$?
[ "$RC" = 0 ] || { echo "--- out ---"; cat "$WORK/post.out"; \
    echo "--- err ---"; cat "$WORK/post.err"; _fail "parent post exit $RC"; }

# the recursion happened (the sub committed, the parent committed the bump).
DOGTIP1=$(_subtip "$P/dog"); _is40 "$DOGTIP1" "dog tip1"
[ "$DOGTIP1" != "$DOGTIP0" ] || _fail "sub dog did NOT commit — post never recursed"
TOP1=$(_subtip "$P"); _is40 "$TOP1" "P tip1"
[ "$TOP1" != "$TOP0" ] || _fail "parent P did NOT commit"

# THE cell: the parent's OWN dirty file is IN the parent commit, not dropped.
GOT=$(_blobat "$P" TOP.c)
[ "$GOT" = "top payload v2 EDITED" ] \
    || _fail "parent commit carries TOP.c = '$GOT', want 'top payload v2 EDITED' — the sub gitlink bump flipped the parent to selective and DROPPED its own dirty file"
# and the sub's change rode along in the same run.
DGOT=$(_blobat "$P/dog" DOG.c)
[ "$DGOT" = "dog payload v2 EDITED" ] \
    || _fail "sub commit carries DOG.c = '$DGOT', want 'dog payload v2 EDITED'"
echo "ok   1. COMMIT-ALL: parent dirty file + sub dirty file in the one post"

# ===== Leg 2: SELECTIVE — exactly the staged set, sub bump included ==========
Q="$WORK/Q"; mkdir -p "$Q/.be"
( cd "$Q" && printf 'top payload v1\n' > TOP.c && printf 'other v1\n' > OTHER.c \
    && "$BE" post '#parent initial' ) >/dev/null 2>&1 || _fail "parent Q setup"
_mount "$Q" dog
QTOP0=$(_subtip "$Q"); _is40 "$QTOP0" "Q tip0"

# a REAL user put of ONE parent file; a REAL put inside the sub (so the sub
# commits and postSubs writes the gitlink bump row); OTHER.c dirty-UNSTAGED.
printf 'top payload v2 STAGED\n' > "$Q/TOP.c"
printf 'other v2 UNSTAGED\n' > "$Q/OTHER.c"
printf 'dog payload v2 STAGED\n' > "$Q/dog/DOG.c"
( cd "$Q" && "$BE" put TOP.c ) >"$WORK/put.out" 2>"$WORK/put.err" \
    || { cat "$WORK/put.err"; _fail "put TOP.c"; }
( cd "$Q/dog" && "$BE" put DOG.c ) >"$WORK/put2.out" 2>"$WORK/put2.err" \
    || { cat "$WORK/put2.err"; _fail "put DOG.c inside dog"; }

RC=0
( cd "$Q" && "$JABC" post '#POST-034: selective' ) \
    >"$WORK/post2.out" 2>"$WORK/post2.err" || RC=$?
[ "$RC" = 0 ] || { echo "--- out ---"; cat "$WORK/post2.out"; \
    echo "--- err ---"; cat "$WORK/post2.err"; _fail "selective post exit $RC"; }

QTOP1=$(_subtip "$Q"); _is40 "$QTOP1" "Q tip1"
[ "$QTOP1" != "$QTOP0" ] || _fail "selective: parent Q did NOT commit"
[ "$(_subtip "$Q/dog")" != "$DOGTIP0" ] || _fail "selective: staged sub did NOT commit"
QGOT=$(_blobat "$Q" TOP.c)
[ "$QGOT" = "top payload v2 STAGED" ] \
    || _fail "selective: staged TOP.c committed as '$QGOT', want 'top payload v2 STAGED'"
QOTH=$(_blobat "$Q" OTHER.c)
[ "$QOTH" = "other v1" ] \
    || _fail "selective: UNSTAGED OTHER.c committed as '$QOTH', want the baseline 'other v1' — selective must commit exactly the staged set"
echo "ok   2. SELECTIVE: exactly the staged set (sub bump included)"

pass
