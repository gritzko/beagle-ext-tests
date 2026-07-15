#!/bin/sh
# test/post/uniform — DIS-061: a commit advances the WORKTREE only; the tracked
# branch tip moves ONLY by an explicit `post ?branch` (RULED UNIFORM 2026-07-13).
#   A. plain `#c2` on trunk → wt goes ahead, trunk ref UNMOVED; then `post ?`
#      (cur's OWN branch) FF-advances trunk to the wt base (own-branch is THE
#      standard advance, not a refusal).
#   B. an absolute query `post ?/x/y` routes through the branch codec: the refs
#      row is keyed by the NORMALIZED key `y`, never the literal `/x/y`.
. "$(dirname "$0")/../../lib/postcase.sh"

# store TRUNK tip sha of a clone (via store.js — the reader post.js uses).
_tip() {
    cat > "$WORK/.tip.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const info=be.treeAt(process.argv[2]);
const k=store.open(info.storePath,info.project);
const u=utf8.Encode((k.resolveRef("")||"")+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.tip.js" "$1" "$BEDIR" 2>/dev/null
}

# the wt's current cur (base) tip via wtlog.curTip() — the WORKTREE hash.
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

# list every LOCAL tip KEY in a clone's store (one per line) — proves whether a
# bogus literal-keyed ref row (`/x/y`) was minted vs the normalized `y`.
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

# Origin store: post c1 (a.txt=A).
ORG="$WORK/org"; mkdir -p "$ORG"; ( cd "$ORG" && mkdir .be && {
    printf 'A\n' > a.txt
    "$BE" post '#c1' >/dev/null 2>&1
} )

# --- A. commit advances the WT only; `post ?` FFs cur's OWN branch ----------
rm -rf "$WORK/a"; mkdir "$WORK/a"
( cd "$WORK/a" && "$BE" get "file://$ORG/.be" >/dev/null 2>&1 )
A_C1=$(_tip "$WORK/a")
( cd "$WORK/a" && printf 'A2\n' > a.txt && "$BE" put a.txt >/dev/null 2>&1 && \
  "$JABC" post '#c2' ) >"$WORK/a.out" 2>"$WORK/a.err" || _fail "plain post failed: $(cat "$WORK/a.err")"
A_CUR=$(_cur "$WORK/a")
[ "$A_CUR" != "$A_C1" ] || _fail "plain post did NOT advance the worktree (cur still c1)"
# the RULED behavior: the trunk ref stays put after a commit.
[ "$(_tip "$WORK/a")" = "$A_C1" ] \
    || _fail "commit MOVED the trunk ref (uniform ruling: a commit advances the WT only)"
# `post ?` = advance cur's OWN branch (trunk) — must FF, not refuse.
( cd "$WORK/a" && "$JABC" post '?' ) >"$WORK/a2.out" 2>"$WORK/a2.err" \
    || _fail "post '?' (own branch FF) refused: $(cat "$WORK/a2.err")"
[ "$(_tip "$WORK/a")" = "$A_CUR" ] \
    || _fail "post '?' did NOT FF trunk to the wt base ($A_CUR; got $(_tip "$WORK/a"))"

# --- B. absolute `?/x/y` routes through the branch codec (no bogus key) ------
rm -rf "$WORK/b"; mkdir "$WORK/b"
( cd "$WORK/b" && "$BE" get "file://$ORG/.be" >/dev/null 2>&1 )
( cd "$WORK/b" && printf 'B2\n' > a.txt && "$BE" put a.txt >/dev/null 2>&1 && \
  "$JABC" post '#c2b' >/dev/null 2>&1 ) || _fail "b: local c2 failed"
B_CUR=$(_cur "$WORK/b")
( cd "$WORK/b" && "$JABC" post '?/x/y' ) >"$WORK/b.out" 2>"$WORK/b.err" \
    || _fail "post '?/x/y' failed: $(cat "$WORK/b.err")"
# the refs row must be keyed by the NORMALIZED key `y`, never the literal `/x/y`.
_tipkeys "$WORK/b" | grep -qx '/x/y' \
    && _fail "post '?/x/y' minted a bogus literal-keyed ref row (/x/y) — codec bypassed"
[ "$(_branch_tip "$WORK/b" y)" = "$B_CUR" ] \
    || _fail "post '?/x/y' did NOT advance the normalized branch y to cur ($B_CUR; got $(_branch_tip "$WORK/b" y))"

pass
