#!/bin/sh
# test/post/sub-msg-spice — POST-027 cell 2x: the recursed SUB commit MESSAGE.
# Spec: /wiki/POST.mkd §"Summary of invocation patterns" row 2, nested bullet:
# "a recursed sub's commit may spice the parent's message up with the sub
# path, like `[dog]` or `[dog/abc]`".  Parent P mounts a sub `dog` (the
# sub/nestedpost keeper-free mount recipe: a `jab get` clone into a subdir
# plants a `.be` FILE redirect; the gitlink is seeded into the wtlog and
# committed).  A change is staged INSIDE dog, the parent `post '#T-1: fix'`
# recurses — the sub's new commit message must be the parent's message SPICED
# with the sub path: `T-1: fix [dog]`.
#
# EXPECTED RED today: the implementation passes the parent's message to the
# recursed sub VERBATIM (`T-1: fix`, no `[dog]` spice) — POST-027 lists the
# spice as unimplemented.  This test is the repro that drives the fix; it
# fails on the spec assertion (the message-shape check), nothing earlier.
. "$(dirname "$0")/../../lib/postcase.sh"

# _subtip WT — a wt's current cur tip via be.treeAt + the wtlog reader (works
# for the mounted sub too: its `.be` is a FILE redirect).
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

# _msg WT — decode the MESSAGE body of a wt's tip commit (the bytes after the
# header block's blank line), trailing newlines stripped.  The sub/selfloop
# pattern: read the object through the store reader, never od/grep `.be`.
_msg() {
    cat > "$WORK/.msg.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
const k=store.open(info.storePath,info.project);
const c=wtlog.open(info).curTip();
let msg="";
if(c&&c.sha){const o=k.getObject(c.sha);
  if(o){const s=utf8.Decode(o.bytes);const i=s.indexOf("\n\n");
    if(i>=0)msg=s.slice(i+2).replace(/\n+$/,"");}}
const u=utf8.Encode(msg+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.msg.js" "$1" "$BEDIR" 2>/dev/null
}

# _pinrow SUBPATH WTLOG SHA — seed a `put <subpath>#<sha>` gitlink-bump row
# (the sub/nestedpost recipe: jab has no CLI spelling for a manual gitlink
# pin, so the first gitlink goes straight into the wtlog; the next post folds
# it into a 160000 baseline entry).
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

# --- fixture: parent P with the sub `dog` mounted and gitlinked ---------------
DOGSRC="$WORK/dogsrc"; mkdir -p "$DOGSRC/.be"
( cd "$DOGSRC" && printf 'dog payload v1\n' > DOG.c && "$BE" post '#dog initial' ) \
    >/dev/null 2>&1 || _fail "dog source store setup"
DOGTIP0=$(_subtip "$DOGSRC"); _is40 "$DOGTIP0" "dog tip0"

P="$WORK/P"; mkdir -p "$P/.be"
( cd "$P" && printf 'top payload v1\n' > TOP.c && "$BE" post '#parent initial' ) \
    >/dev/null 2>&1 || _fail "parent P setup"

mkdir -p "$P/dog"
( cd "$P/dog" && "$BE" get "file://$DOGSRC/.be#$DOGTIP0" ) >"$WORK/getdog.out" 2>&1 \
    || { cat "$WORK/getdog.out"; _fail "mount dog"; }
[ -f "$P/dog/.be" ] || _fail "P/dog/.be not a FILE redirect (dog not mounted)"
_pinrow "dog" "$P/.be/wtlog" "$DOGTIP0"
( cd "$P" && "$BE" post '#mount dog' ) >"$WORK/mount.out" 2>&1 \
    || { cat "$WORK/mount.out"; _fail "commit dog gitlink"; }
TOP0=$(_subtip "$P"); _is40 "$TOP0" "top tip0"

# --- stage INSIDE dog, post the PARENT message ------------------------------
printf 'dog payload v2 EDITED\n' > "$P/dog/DOG.c"
( cd "$P/dog" && "$BE" put DOG.c ) >"$WORK/put.out" 2>"$WORK/put.err" \
    || { cat "$WORK/put.err"; _fail "put DOG.c inside dog"; }

RC=0
( cd "$P" && "$JABC" post '#T-1: fix' ) >"$WORK/post.out" 2>"$WORK/post.err" || RC=$?
[ "$RC" = 0 ] || { echo "--- out ---"; cat "$WORK/post.out"; \
    echo "--- err ---"; cat "$WORK/post.err"; _fail "parent post exit $RC"; }

# the recursion happened: dog committed, the parent committed the bump.
DOGTIP1=$(_subtip "$P/dog"); _is40 "$DOGTIP1" "dog tip1"
[ "$DOGTIP1" != "$DOGTIP0" ] || _fail "sub dog did NOT commit — parent post never recursed"
TOP1=$(_subtip "$P"); _is40 "$TOP1" "top tip1"
[ "$TOP1" != "$TOP0" ] || _fail "parent P did NOT commit the dog gitlink bump"

# THE cell: the sub's commit message is the parent's message SPICED with the
# sub path — `T-1: fix [dog]` (row 2 nested bullet).  RED today: verbatim.
DOGMSG=$(_msg "$P/dog")
[ "$DOGMSG" = "T-1: fix [dog]" ] \
    || _fail "sub commit message is '$DOGMSG', want 'T-1: fix [dog]' — the [dog] spice (POST.mkd row 2) is not applied"

pass
