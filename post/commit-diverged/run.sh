#!/bin/sh
# test/post/commit-diverged — POST-027 cell 2-v (defensive): a `#msg` COMMIT on
# a wt whose TRACKED branch has DIVERGED must SUCCEED — a commit has no ref
# gate (DIS-076; the old commit-time POSTNOFF is gone, see post/refuse).
# Spec: /wiki/POST.mkd §"Summary of invocation patterns" row 2 — "`jab post
# '#msg'` makes a commit; the wt base moves, no ref ever does".  Fixture (the
# post/refuse non-FF build): X and Y are sibling redirect clones SHARING the
# origin store; Y publishes `?feat` at the common base, X switches to TRACK
# feat, then BOTH sides commit past the base — Y FFs feat to its own tip, so
# feat and X's cur are now DIVERGED.  X's `post '#anyway'` must still commit:
# cur advances, NO POSTNOFF, and feat stays at Y's tip.
. "$(dirname "$0")/../../lib/postcase.sh"

# the wt's current cur (base) tip via wtlog.curTip() — the WORKTREE hash.
_tip() {
    cat > "$WORK/.tip.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
const c=wtlog.open(info).curTip();
const u=utf8.Encode(((c&&c.sha)||"")+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.tip.js" "$1" "$BEDIR" 2>/dev/null
}

# a branch's REFS tip as seen from DIR (shared/store.js resolveRef — the same
# reader post.js uses; never grep a `.be/refs` ULOG).
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

# Origin store: post c1 (the common base).
ORG="$WORK/org"; mkdir -p "$ORG"; ( cd "$ORG" && mkdir .be && {
    printf 'A\n' > a.txt; printf 'B\n' > b.txt
    "$BE" post '#c1' >/dev/null 2>&1
} )
ORG_TIP=$(_orgtip "$ORG")
[ -n "$ORG_TIP" ] || _fail "origin: no c1 tip"

# X and Y: sibling redirect clones sharing the origin store, both at c1.
mkdir "$WORK/x"; ( cd "$WORK/x" && "$BE" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 )
mkdir "$WORK/y"; ( cd "$WORK/y" && "$BE" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 )

# Y publishes ?feat at the common base; X switches to TRACK feat (still at c1).
( cd "$WORK/y" && "$JABC" post '?feat' ) >/dev/null 2>&1 \
    || _fail "y: publish ?feat at the base failed"
( cd "$WORK/x" && "$JABC" get '?feat' ) >/dev/null 2>&1 \
    || _fail "x: switch to track ?feat failed"

# X commits past the base on its own line.
( cd "$WORK/x" && printf 'X2\n' > a.txt && "$BE" put a.txt >/dev/null 2>&1 && \
  "$JABC" post '#x1' >/dev/null 2>&1 ) || _fail "x: post x1 failed"
X_TIP=$(_tip "$WORK/x")
[ -n "$X_TIP" ] && [ "$X_TIP" != "$ORG_TIP" ] || _fail "x: cur did not move past the base"

# Y commits past the base too and FFs feat onto its own tip → feat has now
# DIVERGED from X's cur (common ancestor c1, both sides moved).
( cd "$WORK/y" && printf 'B2\n' > b.txt && "$BE" put b.txt >/dev/null 2>&1 && \
  "$JABC" post '#y1' >/dev/null 2>&1 && "$JABC" post '?feat' >/dev/null 2>&1 ) \
    || _fail "y: advance + FF ?feat failed"
Y_TIP=$(_tip "$WORK/y")
FEAT0=$(_ref "$WORK/x" feat)
[ "$FEAT0" = "$Y_TIP" ] || _fail "fixture: feat ($FEAT0) not at y's tip ($Y_TIP)"
[ "$FEAT0" != "$X_TIP" ] && [ "$FEAT0" != "$ORG_TIP" ] \
    || _fail "fixture: feat did not diverge from x (feat=$FEAT0 x=$X_TIP base=$ORG_TIP)"

# The cell: X's `#anyway` COMMIT on the diverged-track wt must SUCCEED — no
# POSTNOFF (a commit has no ref gate), cur advances, feat untouched.
printf 'X3\n' > "$WORK/x/a.txt"
( cd "$WORK/x" && "$BE" put a.txt ) >/dev/null 2>&1 || _fail "x: put for #anyway failed"
RC=0
( cd "$WORK/x" && "$JABC" post '#anyway' ) >"$WORK/x.out" 2>"$WORK/x.err" || RC=$?
if [ "$RC" -ne 0 ]; then
    echo "--- out ---"; cat "$WORK/x.out"
    echo "--- err ---"; cat "$WORK/x.err"
    _fail "commit on a diverged-track wt exit $RC — DIS-076: a commit has NO ref gate"
fi
grep -q "can not be fast-forwarded" "$WORK/x.err" \
    && _fail "commit emitted the non-FF refusal on a diverged track — the ref gate belongs to the advance arm only"
X_TIP2=$(_tip "$WORK/x")
[ -n "$X_TIP2" ] && [ "$X_TIP2" != "$X_TIP" ] \
    || _fail "cur did not advance on #anyway (still $X_TIP)"
[ "$(_ref "$WORK/x" feat)" = "$FEAT0" ] \
    || _fail "the commit MOVED the diverged feat ref ($FEAT0 -> $(_ref "$WORK/x" feat))"

pass
