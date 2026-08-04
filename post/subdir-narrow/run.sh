#!/bin/sh
# test/post/subdir-narrow — URI-010: the POST.mkd Path slot resolves against the
# INVOCATION SUBDIR (the run's context dir), re-anchored at the wt root.
#   leg 1  `cd sub && jab post . '#msg'`      narrows to `sub` — root.txt's dirt
#          must NOT land.  Pre-fix a bare `.` was not even a Path slot
#          (isPathSlot wanted a `/`), so it was swallowed as a message word and
#          the commit-all mode committed EVERYTHING.
#   leg 2  `cd sub && jab post d/x.txt '#msg'` narrows to `sub/d/x.txt` — pre-fix
#          the raw `d/x.txt` matched the ROOT decoy `d/x.txt` instead.
# The wt-ROOT `.` case (must narrow to nothing) is test/post/rootdot-narrow.
. "$(dirname "$0")/../../lib/postcase.sh"

# read the committed blob at PATH in a wt's own cur tip (the slots/ probe);
# empty when the path is absent from the commit.
_blob_at() {   # _blob_at DIR PATH
    cat > "$WORK/.blob.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
const k=store.open(info.storePath,info.project);
const c=wtlog.open(info).curTip();
const tip=(c&&c.sha)||"";
let out="";
if (tip){ const tree=k.commitTree(tip);
  const leaf=k.descendPath(tree, process.argv[4].split("/"));
  if (leaf && leaf.kind!=="tree"){ const o=k.getObject(leaf.sha); if(o) out=utf8.Decode(o.bytes); } }
const u=utf8.Encode(out);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.blob.js" "$1" "$BEDIR" "$2" 2>/dev/null
}

# ===== fixture: origin with a root file, a sub/ file and a d/x.txt decoy ====
ORG="$WORK/org"; mkdir -p "$ORG"; ( cd "$ORG" && mkdir .be && {
    mkdir -p sub/d d
    printf 'R1\n' > root.txt
    printf 'S1\n' > sub/s.txt
    printf 'X1\n' > sub/d/x.txt
    printf 'DX1\n' > d/x.txt
    "$BE" post '#c1' >/dev/null 2>&1
} )
ORG_TIP=$(_orgtip "$ORG")
[ -n "$ORG_TIP" ] || _fail "fixture: no origin tip"

# a fresh clone of the origin store with EVERY file dirtied (nothing staged →
# post's commit-all mode; the narrow is the only thing keeping files out).
_clone_dirty() {   # _clone_dirty NAME
    rm -rf "$WORK/$1"; mkdir "$WORK/$1"
    ( cd "$WORK/$1" && "$BE" get "file://$ORG/.be#$ORG_TIP" ) >/dev/null 2>&1 \
        || _fail "$1: clone failed"
    ( cd "$WORK/$1" && printf 'R2\n' > root.txt && printf 'S2\n' > sub/s.txt \
        && printf 'X2\n' > sub/d/x.txt && printf 'DX2\n' > d/x.txt )
}

# ===== leg 1: `cd sub && post . '#msg'` narrows to `sub` ====================
_clone_dirty w1
( cd "$WORK/w1/sub" && "$JABC" post . '#narrow to sub' ) \
    >"$WORK/w1.out" 2>"$WORK/w1.err" \
    || _fail "cd sub && post . '#msg' FAILED: $(cat "$WORK/w1.err")"
[ "$(_blob_at "$WORK/w1" sub/s.txt)" = "S2" ] \
    || _fail "post . in sub/ did NOT commit sub/s.txt (got '$(_blob_at "$WORK/w1" sub/s.txt)')"
[ "$(_blob_at "$WORK/w1" sub/d/x.txt)" = "X2" ] \
    || _fail "post . in sub/ did NOT commit sub/d/x.txt (got '$(_blob_at "$WORK/w1" sub/d/x.txt)')"
[ "$(_blob_at "$WORK/w1" root.txt)" = "R1" ] \
    || _fail "post . in sub/ leaked root.txt into the commit (narrow ignored: '$(_blob_at "$WORK/w1" root.txt)')"
[ "$(_blob_at "$WORK/w1" d/x.txt)" = "DX1" ] \
    || _fail "post . in sub/ leaked d/x.txt into the commit (narrow ignored)"

# ===== leg 2: `cd sub && post d/x.txt '#msg'` narrows to `sub/d/x.txt` ======
_clone_dirty w2
( cd "$WORK/w2/sub" && "$JABC" post d/x.txt '#narrow to sub/d/x.txt' ) \
    >"$WORK/w2.out" 2>"$WORK/w2.err" \
    || _fail "cd sub && post d/x.txt '#msg' FAILED: $(cat "$WORK/w2.err")"
[ "$(_blob_at "$WORK/w2" sub/d/x.txt)" = "X2" ] \
    || _fail "post d/x.txt in sub/ did NOT commit sub/d/x.txt (got '$(_blob_at "$WORK/w2" sub/d/x.txt)')"
[ "$(_blob_at "$WORK/w2" d/x.txt)" = "DX1" ] \
    || _fail "post d/x.txt in sub/ hit the ROOT decoy d/x.txt (cwd ignored: '$(_blob_at "$WORK/w2" d/x.txt)')"
[ "$(_blob_at "$WORK/w2" sub/s.txt)" = "S1" ] \
    || _fail "post d/x.txt in sub/ leaked sub/s.txt into the commit"
[ "$(_blob_at "$WORK/w2" root.txt)" = "R1" ] \
    || _fail "post d/x.txt in sub/ leaked root.txt into the commit"

pass
