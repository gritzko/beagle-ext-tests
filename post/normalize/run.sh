#!/bin/sh
# test/post/normalize — DIS-076: an absolute dotted Query (`?/jab/.beagle`,
# a pin-branch shape) must route through branchlib.parse/key — resolving the
# stored `.beagle` key, minting no bogus literal-keyed ref row.
. "$(dirname "$0")/../../lib/postcase.sh"

# list every LOCAL tip KEY in a clone's store (one per line).
_tipkeys() {
    cat > "$WORK/.keys.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const info=be.treeAt(process.argv[2]);
const k=store.open(info.storePath,info.project);
let out="";k.eachTip(function(t){out+=t.key+"\n";});
const u=utf8.Encode(out);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.keys.js" "$1" "$BEDIR" 2>/dev/null
}

# the wt's current cur (base) tip via wtlog.curTip().
_cur() {
    cat > "$WORK/.cur.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
const c=wtlog.open(info).curTip();
const u=utf8.Encode(((c&&c.sha)||"")+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.cur.js" "$1" "$BEDIR" 2>/dev/null
}

# store tip sha of a NAMED branch (empty when absent).
_branch_tip() {   # _branch_tip DIR BRANCH
    cat > "$WORK/.btip.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const info=be.treeAt(process.argv[2]);
const k=store.open(info.storePath,info.project);
const u=utf8.Encode((k.resolveRef(process.argv[4])||"")+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.btip.js" "$1" "$BEDIR" "$2" 2>/dev/null
}

# Origin store: post c1.
ORG="$WORK/org"; mkdir -p "$ORG"; ( cd "$ORG" && mkdir .be && {
    printf 'A\n' > a.txt
    "$BE" post '#c1' >/dev/null 2>&1
} )
# DIS-076: a bare post never mints a ref — pin the clone at ORG's own cur tip.
_orgtip() { ( cd "$1" && "$JABC" refs 2>/dev/null ) | sed -n 's/^cur: *//p'; }
ORG_TIP=$(_orgtip "$ORG")

rm -rf "$WORK/b"; mkdir "$WORK/b"
( cd "$WORK/b" && "$BE" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 )
( cd "$WORK/b" && printf 'B2\n' > a.txt && "$BE" put a.txt >/dev/null 2>&1 && \
  "$JABC" post '#c2' >/dev/null 2>&1 ) || _fail "b: local c2 failed"
B_CUR=$(_cur "$WORK/b")

# advance to the dotted absolute query (a pin-branch shape) — must resolve
# via branchlib, never mint a literal `/jab/.beagle` key.
( cd "$WORK/b" && "$JABC" post '?/jab/.beagle' ) >"$WORK/b.out" 2>"$WORK/b.err" \
    || _fail "post '?/jab/.beagle' failed: $(cat "$WORK/b.err")"

_tipkeys "$WORK/b" | grep -qx '/jab/.beagle' \
    && _fail "post '?/jab/.beagle' minted a bogus literal-keyed ref row (/jab/.beagle) — codec bypassed"
[ "$(_branch_tip "$WORK/b" .beagle)" = "$B_CUR" ] \
    || _fail "post '?/jab/.beagle' did NOT advance the normalized branch .beagle to cur ($B_CUR; got $(_branch_tip "$WORK/b" .beagle))"

pass
