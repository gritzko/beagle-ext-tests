#!/bin/sh
# test/post/rootdot-narrow — URI-010 guard: at the WT ROOT, `jab post . '#msg'`
# narrows to NOTHING and commits the whole tree.  `.` at the root resolves (via
# discover.argRel) to the dir-form `./`, which fold-decide.js makeNarrow's
# leading-`./` shed decodes back to "no narrow".  Retiring that shed makes this
# case match no path at all → "no changes since base".  Sibling of
# test/post/subdir-narrow (the same `.` INSIDE a subdir, which DOES narrow).
. "$(dirname "$0")/../../lib/postcase.sh"

# read the committed blob at PATH in a wt's own cur tip (the slots/ probe).
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

ORG="$WORK/org"; mkdir -p "$ORG"; ( cd "$ORG" && mkdir .be && {
    mkdir -p sub
    printf 'R1\n' > root.txt
    printf 'S1\n' > sub/s.txt
    "$BE" post '#c1' >/dev/null 2>&1
} )
ORG_TIP=$(_orgtip "$ORG")
[ -n "$ORG_TIP" ] || _fail "fixture: no origin tip"

rm -rf "$WORK/w"; mkdir "$WORK/w"
( cd "$WORK/w" && "$BE" get "file://$ORG/.be#$ORG_TIP" ) >/dev/null 2>&1 \
    || _fail "clone failed"
( cd "$WORK/w" && printf 'R2\n' > root.txt && printf 'S2\n' > sub/s.txt )

( cd "$WORK/w" && "$JABC" post . '#root dot' ) >"$WORK/w.out" 2>"$WORK/w.err" \
    || _fail "post . at the wt root FAILED: $(cat "$WORK/w.err")"
grep -q "no changes since base" "$WORK/w.err" \
    && _fail "post . at the wt root matched nothing (the ./-shed was retired?)"
[ "$(_blob_at "$WORK/w" root.txt)" = "R2" ] \
    || _fail "post . at the wt root did NOT commit root.txt (got '$(_blob_at "$WORK/w" root.txt)')"
[ "$(_blob_at "$WORK/w" sub/s.txt)" = "S2" ] \
    || _fail "post . at the wt root did NOT commit sub/s.txt (got '$(_blob_at "$WORK/w" sub/s.txt)')"

pass
