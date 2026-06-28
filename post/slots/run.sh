#!/bin/sh
# test/post/slots — DIS-054 step 2: REAL implementations of POST.mkd's URI
# slots in the JS `be post` (was: refuse-loud).  POST.mkd is authoritative and
# OVERRIDES the native impl where they disagree (native carries the POST-024
# misroute bugs).  We assert the SPEC behaviour per slot:
#   * Query `?other#msg` — COMMIT onto ?other + UNTIE the wt from cur: the
#     ?other ref advances to the new commit, cur (trunk) is UNTOUCHED, and the
#     wt now tracks ?other (its wtlog post row carries ?other).
#   * Query `?branch` (bare) — FF-advance ?branch to cur's tip (no commit), cur
#     untouched; absent target ?branch is CREATED at cur's tip.
#   * Path `./path` / `dir/file` — NARROW the commit to that path: only the
#     named path's change lands; a sibling staged change does NOT.
#   * Host `//host` / `ssh://…?b` / `be://…?b` — push is a separate subsystem
#     (no JS receive-pack send-pack yet); still refuse-loud POSTPUSH, never a
#     silent local commit (DIS-054 design fork — its own ticket).
# A populated slot must never silently local-commit onto cur.  The local-FF
# `#msg` path must still commit (no regression).
. "$(dirname "$0")/../../lib/postcase.sh"

# store TRUNK tip sha of a clone (via store.js, the reader post.js uses).
_tip() {
    cat > "$WORK/.tip.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const info=be.find(process.argv[2]);
const k=store.open(info.storePath,info.project);
const u=utf8.Encode((k.resolveRef("")||"")+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.tip.js" "$1" "$BEDIR" 2>/dev/null
}

# store tip sha of a NAMED branch in a clone's store (empty when absent).
_branch_tip() {   # _branch_tip DIR BRANCH
    cat > "$WORK/.btip.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const info=be.find(process.argv[2]);
const k=store.open(info.storePath,info.project);
const u=utf8.Encode((k.resolveRef(process.argv[4])||"")+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.btip.js" "$1" "$BEDIR" "$2" 2>/dev/null
}

# the branch the wt currently tracks (curTip().branch), via wtlog.js.
_cur_branch() {   # _cur_branch DIR
    cat > "$WORK/.cbr.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.find(process.argv[2]);
const c=wtlog.open(info).curTip();
const u=utf8.Encode(((c&&c.branch)||"")+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.cbr.js" "$1" "$BEDIR" 2>/dev/null
}

# read the committed git blob at PATH in a clone's TRUNK tip tree (empty when
# absent) — proves a path actually landed (or did not) in the commit.
_blob_at() {   # _blob_at DIR PATH [BRANCH]
    cat > "$WORK/.blob.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const info=be.find(process.argv[2]);
const k=store.open(info.storePath,info.project);
const tip=k.resolveRef(process.argv[5]||"");
let out="";
if (tip){ const tree=k.commitTree(tip);
  const seg=process.argv[4].replace(/^\.\//,"").split("/");
  const leaf=k.descendPath(tree, seg);
  if (leaf && leaf.kind!=="tree"){ const o=k.getObject(leaf.sha); if(o) out=utf8.Decode(o.bytes); } }
const u=utf8.Encode(out);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.blob.js" "$1" "$BEDIR" "$2" "${3:-}" 2>/dev/null
}

# Origin store: post c1 (a.txt=A).
ORG="$WORK/org"; mkdir -p "$ORG"; ( cd "$ORG" && mkdir .be && {
    printf 'A\n' > a.txt
    "$BE" post '#c1' >/dev/null 2>&1
} )

# A fresh clone of the origin store with one STAGED change to a.txt.
_clone_staged() {
    rm -rf "$WORK/$1"; mkdir "$WORK/$1"
    ( cd "$WORK/$1" && "$BE" get "file://$ORG/.be?/org" >/dev/null 2>&1 )
    ( cd "$WORK/$1" && printf 'CHANGED\n' > a.txt && "$BE" put a.txt >/dev/null 2>&1 )
}

# Assert: `jab post <URI>` REFUSES via <CODE>, exits non-zero, tip UNCHANGED.
_refuse() {   # _refuse DIR URI CODE
    _clone_staged "$1"
    _t0=$(_tip "$WORK/$1")
    if ( cd "$WORK/$1" && "$JABC" post "$2" ) >"$WORK/$1.out" 2>"$WORK/$1.err"; then
        _fail "post '$2' did NOT refuse (silent local commit?): $(cat "$WORK/$1.out")"
    fi
    grep -q "$3" "$WORK/$1.err" \
        || _fail "post '$2' refused but not via $3: $(cat "$WORK/$1.err")"
    [ "$(_tip "$WORK/$1")" = "$_t0" ] \
        || _fail "post '$2' mutated the store tip (must be all-or-nothing)"
}

# === Host slot (push) — DESIGN FORK: still refuse-loud POSTPUSH =============
# A correct JS push needs a receive-pack send-pack client (object-closure walk,
# pack build, ref-update command, report-status drain) that shared/wire.js does
# not yet have (it is fetch-only).  Per the DIS-054 fork, push stays an honest
# refuse — never a silent local commit — and lands in its own ticket.
_refuse h1 "ssh://host/repo?branch" POSTPUSH
_refuse h2 "//host"                 POSTPUSH
_refuse h3 "be://host?branch"       POSTPUSH

# === Query slot: ?other#msg — COMMIT onto ?other + UNTIE wt from cur ========
_clone_staged q1
Q1_TRUNK0=$(_tip "$WORK/q1")
( cd "$WORK/q1" && "$JABC" post '?other#commit on other' ) >"$WORK/q1.out" 2>"$WORK/q1.err" \
    || _fail "post '?other#msg' FAILED: $(cat "$WORK/q1.err")"
Q1_OTHER=$(_branch_tip "$WORK/q1" other)
[ -n "$Q1_OTHER" ] || _fail "post '?other#msg' did NOT advance ?other"
[ "$Q1_OTHER" != "$Q1_TRUNK0" ] || _fail "post '?other#msg' landed ?other at the OLD tip (no commit)"
[ "$(_tip "$WORK/q1")" = "$Q1_TRUNK0" ] \
    || _fail "post '?other#msg' moved TRUNK (must commit onto ?other only)"
[ "$(_cur_branch "$WORK/q1")" = "other" ] \
    || _fail "post '?other#msg' did NOT untie the wt to ?other (cur=$(_cur_branch "$WORK/q1"))"
# the new commit on ?other carries the staged change.
[ "$(_blob_at "$WORK/q1" a.txt other)" = "CHANGED" ] \
    || _fail "post '?other#msg' commit on ?other missing the staged a.txt change"

# === Query slot: ?branch (bare) — FF-advance ?branch to cur's tip ==========
# Clone, commit locally onto trunk (advance cur), THEN `?feat` advances feat to
# cur's tip with NO new commit.  feat does not pre-exist → created at cur's tip.
rm -rf "$WORK/q2"; mkdir "$WORK/q2"
( cd "$WORK/q2" && "$BE" get "file://$ORG/.be?/org" >/dev/null 2>&1 )
( cd "$WORK/q2" && printf 'C2\n' > a.txt && "$BE" put a.txt >/dev/null 2>&1 && \
  "$JABC" post '#c2' >/dev/null 2>&1 ) || _fail "q2 local c2 post failed"
Q2_CUR=$(_tip "$WORK/q2")
( cd "$WORK/q2" && "$JABC" post '?feat' ) >"$WORK/q2.out" 2>"$WORK/q2.err" \
    || _fail "post '?feat' FAILED: $(cat "$WORK/q2.err")"
[ "$(_branch_tip "$WORK/q2" feat)" = "$Q2_CUR" ] \
    || _fail "post '?feat' did NOT FF-advance feat to cur's tip ($Q2_CUR; got $(_branch_tip "$WORK/q2" feat))"
[ "$(_tip "$WORK/q2")" = "$Q2_CUR" ] \
    || _fail "post '?feat' moved trunk (a bare ?branch advance makes NO commit)"

# === Path slot: ./path — NARROW the commit to that path ====================
# Origin with TWO files; clone, change BOTH, stage BOTH, then `./a.txt` commits
# ONLY a.txt — b.txt's change must NOT land in the commit.
ORG2="$WORK/org2"; mkdir -p "$ORG2"; ( cd "$ORG2" && mkdir .be && {
    printf 'A\n' > a.txt; printf 'B\n' > b.txt
    "$BE" post '#c1' >/dev/null 2>&1
} )
rm -rf "$WORK/p1"; mkdir "$WORK/p1"
( cd "$WORK/p1" && "$BE" get "file://$ORG2/.be?/org2" >/dev/null 2>&1 )
( cd "$WORK/p1" && printf 'A2\n' > a.txt && printf 'B2\n' > b.txt && \
  "$BE" put a.txt b.txt >/dev/null 2>&1 )
( cd "$WORK/p1" && "$JABC" post './a.txt#narrow a only' ) >"$WORK/p1.out" 2>"$WORK/p1.err" \
    || _fail "post './a.txt#msg' FAILED: $(cat "$WORK/p1.err")"
[ "$(_blob_at "$WORK/p1" a.txt)" = "A2" ] \
    || _fail "post './a.txt' did NOT commit the a.txt change (got '$(_blob_at "$WORK/p1" a.txt)')"
[ "$(_blob_at "$WORK/p1" b.txt)" = "B" ] \
    || _fail "post './a.txt' leaked the b.txt change into the commit (narrow failed: '$(_blob_at "$WORK/p1" b.txt)')"

# === Path slot: dir/file (no leading ./) — narrow to a subtree path ========
ORG3="$WORK/org3"; mkdir -p "$ORG3"; ( cd "$ORG3" && mkdir .be && {
    mkdir src; printf 'X\n' > src/a.txt; printf 'B\n' > b.txt
    "$BE" post '#c1' >/dev/null 2>&1
} )
rm -rf "$WORK/p2"; mkdir "$WORK/p2"
( cd "$WORK/p2" && "$BE" get "file://$ORG3/.be?/org3" >/dev/null 2>&1 )
( cd "$WORK/p2" && printf 'X2\n' > src/a.txt && printf 'B2\n' > b.txt && \
  "$BE" put src/a.txt b.txt >/dev/null 2>&1 )
( cd "$WORK/p2" && "$JABC" post 'src/a.txt#narrow src' ) >"$WORK/p2.out" 2>"$WORK/p2.err" \
    || _fail "post 'src/a.txt#msg' FAILED: $(cat "$WORK/p2.err")"
[ "$(_blob_at "$WORK/p2" src/a.txt)" = "X2" ] \
    || _fail "post 'src/a.txt' did NOT commit src/a.txt (got '$(_blob_at "$WORK/p2" src/a.txt)')"
[ "$(_blob_at "$WORK/p2" b.txt)" = "B" ] \
    || _fail "post 'src/a.txt' leaked b.txt into the commit (narrow failed)"

# === NO REGRESSION: a plain local `#msg` still commits onto cur ============
_clone_staged ok
OK_T0=$(_tip "$WORK/ok")
( cd "$WORK/ok" && "$JABC" post '#local commit' ) >"$WORK/ok.out" 2>"$WORK/ok.err" \
    || _fail "plain local post FAILED (regression): $(cat "$WORK/ok.err")"
[ "$(_tip "$WORK/ok")" != "$OK_T0" ] \
    || _fail "plain local post did NOT advance the tip (regression)"

pass
