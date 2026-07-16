#!/bin/sh
# test/post/commit-ahead — POST-027 cell 2b-iii: a commit-all `#msg` on a wt
# ALREADY AHEAD of its tracked branch.  Spec: /wiki/POST.mkd §"Summary of
# invocation patterns" row 2 — "`jab post '#msg'` makes a commit; the wt base
# moves, no ref ever does", commit-all bullet: "nothing staged anywhere ⇒
# auto-stage all changes".  Fixture (the post/bare-advance shape-1 build):
# commit c1, publish `?feat` at c1, `get ?feat` (the wt now TRACKS feat),
# commit c2 — the wt is AHEAD of feat.  Then, with NOTHING staged, edit a file
# and `post '#c3'`: the commit-all must SUCCEED, cur advances to c3, and the
# feat ref does NOT move (DIS-076: a commit has no ref gate and never drags
# the track along).
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

# a branch's REFS tip in DIR's store (assertion probe; resolution stays in
# shared/store.js resolveRef — not a re-implementation).
_ref() {   # _ref DIR BRANCH
    cat > "$WORK/.ref.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const info=be.treeAt(process.argv[2]);
const k=store.open(info.storePath,info.project);
const t=k.resolveRef(process.argv[4]||"")||"";
const u=utf8.Encode(t+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.ref.js" "$1" "$BEDIR" "$2" 2>/dev/null
}

# Fixture: c1, publish ?feat, track it, c2 → the wt is AHEAD of feat.
A="$WORK/a"; mkdir -p "$A/.be"
( cd "$A" && printf 'one\n' > f.txt && "$BE" post '#c1' ) >/dev/null 2>&1 \
    || _fail "bootstrap post c1 failed"
( cd "$A" && "$JABC" post '?feat' ) >/dev/null 2>&1 \
    || _fail "publish ?feat failed"
( cd "$A" && "$JABC" get '?feat' ) >/dev/null 2>&1 \
    || _fail "switch to track ?feat failed"
( cd "$A" && printf 'two\n' > f.txt && "$JABC" put f.txt && "$JABC" post '#c2' ) >/dev/null 2>&1 \
    || _fail "post c2 failed"
CUR2=$(_cur "$A")
[ -n "$CUR2" ] || _fail "no cur tip after c2"
FEAT0=$(_ref "$A" feat)
[ -n "$FEAT0" ] && [ "$FEAT0" != "$CUR2" ] \
    || _fail "fixture: feat not behind cur (feat=$FEAT0 cur=$CUR2)"

# NOTHING staged (post c2 consumed the put row); a plain edit → commit-all.
printf 'three\n' > "$A/f.txt"
RC=0
( cd "$A" && "$JABC" post '#c3' ) >"$WORK/c3.out" 2>"$WORK/c3.err" || RC=$?
if [ "$RC" -ne 0 ]; then
    echo "--- out ---"; cat "$WORK/c3.out"
    echo "--- err ---"; cat "$WORK/c3.err"
    _fail "commit-all #c3 on an ahead wt exit $RC — a commit has no ref gate (DIS-076)"
fi

# cur advanced to c3; the tracked feat ref did NOT move.
CUR3=$(_cur "$A")
[ -n "$CUR3" ] && [ "$CUR3" != "$CUR2" ] \
    || _fail "cur did not advance on #c3 (still $CUR2)"
FEAT1=$(_ref "$A" feat)
[ "$FEAT1" = "$FEAT0" ] \
    || _fail "the commit MOVED the tracked feat ref ($FEAT0 -> $FEAT1) — row 2: no ref ever moves on a commit"

pass
