#!/bin/sh
# test/post/commit-selective-first — POST-027 cell 2a-i: SELECTIVE mode on the
# very FIRST commit.  Spec: /wiki/POST.mkd §"Summary of invocation patterns"
# row 2 — "`jab post '#msg'` makes a commit; the wt base moves, no ref ever
# does", selective bullet: "any active put/delete in the mounted tree ⇒ commit
# exactly the staged set".  A FRESH never-committed wt holds TWO new files but
# stages only ONE (`jab put a.txt`); `post '#first'` must mint the BASELINE
# with EXACTLY a.txt — b.txt stays on disk, untracked, staged-out.  Every
# existing 2a coverage (sub/nestedpost, sub/advput) runs selective on an
# already-committed wt; the first-ever-commit selective arm was unpinned.
#
# RED today: the post CRASHES ("JS exception: Error: Not a directory" in
# fold-commit writePack's mmap).  Root cause: in a fresh never-committed wt
# the `jab put` makes the wtlog's ROW 0 a `put a.txt` row, and discover.js
# resolveAnchor's primary-wt branch misreads ANY row-0 uri with a path as a
# store-anchor (repo/get) URI — repoFromBe("a.txt") returns "a.txt", so
# treeAt reports storePath="a.txt" and store.open's shard is the bogus
# "a.txt/.be"; writePack then mmaps a path UNDER a regular file → ENOTDIR.
# The test fails on the "post must succeed" spec assertion (right reason).
. "$(dirname "$0")/../../lib/postcase.sh"

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

# count a.txt / b.txt entries in the wt's committed baseline tree — proves
# WHICH of the two new files the selective first post folded in (assertion
# probe via the store reader post.js itself uses; never od/grep .be).
_ab() {
    cat > "$WORK/.ab.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
const k=store.open(info.storePath,info.project);
const c=wtlog.open(info).curTip();
let a=0,b=0;
if(c&&c.sha){k.readTreeRecursive(k.commitTree(c.sha),function(l){
  if(l.path==="a.txt")a++; if(l.path==="b.txt")b++;});}
const u=utf8.Encode(a+" "+b+"\n");const o=io.buf(u.length+8);o.feed(u);io.write(1,o);
EOF
    "$JABC" "$WORK/.ab.js" "$1" "$BEDIR" 2>/dev/null
}

_is40() {
    case "$1" in
        ????????????????????????????????????????) ;;
        *) _fail "$2: not 40-hex: '$1'" ;;
    esac
}

# FRESH never-committed wt: an empty `.be/` shield, two new files, ONE staged.
W="$WORK/w"; mkdir -p "$W/.be"
printf 'A\n' > "$W/a.txt"
printf 'B\n' > "$W/b.txt"
( cd "$W" && "$JABC" put a.txt ) >"$WORK/put.out" 2>"$WORK/put.err" \
    || _fail "put a.txt in the fresh wt failed: $(cat "$WORK/put.err")"

RC=0
( cd "$W" && "$JABC" post '#first' ) >"$WORK/post.out" 2>"$WORK/post.err" || RC=$?
[ "$RC" = 0 ] || { echo "--- out ---"; cat "$WORK/post.out"; \
    echo "--- err ---"; cat "$WORK/post.err"; \
    _fail "selective first-ever post exit $RC (a staged put in a fresh wt must commit)"; }

# a baseline was born: the wt's own cur is a real tip.
TIP=$(_cur "$W")
_is40 "$TIP" "baseline tip"

# the baseline holds EXACTLY the staged file: a.txt in, b.txt OUT.
AB=$(_ab "$W")
[ "$AB" = "1 0" ] \
    || _fail "baseline tree is [a b]=[$AB], want [1 0] — selective first post must commit exactly the staged a.txt"

# b.txt is untouched on disk (staged-out, still untracked, never deleted).
[ -f "$W/b.txt" ] || _fail "b.txt vanished from the wt (selective post must leave it alone)"
[ "$(cat "$W/b.txt")" = "B" ] || _fail "b.txt content mutated by the selective post"

pass
