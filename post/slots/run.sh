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
#   * Host `//host` / `ssh://…?b` / `be://…?b` — GIT-013 IMPLEMENTED the wire
#     receive-pack send-pack: a Host slot is now a real wire PUSH (NOT a local
#     commit).  We assert (1) a populated host slot FF-PUSHES cur's tip to a
#     LOCAL ssh://localhost bare (the ref advances), and (2) it NEVER silently
#     local-commits onto cur; a bogus `//host` is a push ATTEMPT that fails
#     cleanly (network error), never a POSTPUSH refuse and never a local commit.
# A populated slot must never silently local-commit onto cur.  The local-FF
# `#msg` path must still commit (no regression).
. "$(dirname "$0")/../../lib/postcase.sh"

# store TRUNK tip sha of a clone (via store.js, the reader post.js uses).
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

# store tip sha of a NAMED branch in a clone's store (empty when absent).
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

# the branch the wt currently tracks (curTip().branch), via wtlog.js.
_cur_branch() {   # _cur_branch DIR
    cat > "$WORK/.cbr.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
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
const info=be.treeAt(process.argv[2]);
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
# TEST-003: jab-seeded stores are unnamed-project, so all clones here use bare
# `file://<store>` (no `?/orgN` selector — jab never mints a named shard).
_clone_staged() {
    rm -rf "$WORK/$1"; mkdir "$WORK/$1"
    ( cd "$WORK/$1" && "$BE" get "file://$ORG/.be" >/dev/null 2>&1 )
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

# === Host slot (push) — GIT-013: a Host slot is a real wire PUSH ============
# The JS receive-pack send-pack (shared/wire.js) landed, so a populated host
# slot no longer refuses — it FF-pushes cur's tip to the remote.  Two checks:
#   (1) POSITIVE: `post ssh://localhost/<bare>?master` FF-advances a local bare
#       repo's master to cur's tip (the slot routes to a working push).
#   (2) NEGATIVE: a bogus `//host` (unresolvable) is a push ATTEMPT that fails
#       cleanly — non-zero, NEVER `POSTPUSH`, and NEVER a silent local commit.
# The wire needs git + ssh-to-localhost under $HOME; SKIP that leg cleanly if
# either is missing, but always run the offline NEGATIVE leg.
if command -v git >/dev/null 2>&1 \
   && command -v ssh >/dev/null 2>&1 \
   && case "$WORK" in "$HOME"/*) true;; *) false;; esac \
   && ssh -o BatchMode=yes -o ConnectTimeout=4 localhost true >/dev/null 2>&1
then
    : "${KEEPER_BIN:=$(dirname "$BE")/keeper}"; export KEEPER_BIN
    : "${DOG_REMOTE_PATH:=$(dirname "$BE")}"; export DOG_REMOTE_PATH
    HREL="${WORK#$HOME/}"
    HBARE="$WORK/host.git"
    git init -q --bare -b master "$HBARE"
    git -C "$HBARE" config receive.denyCurrentBranch ignore
    HSEED="$WORK/host.seed"; git init -q -b master "$HSEED"
    git -C "$HSEED" config user.email t@e.st; git -C "$HSEED" config user.name T
    printf 'A\n' > "$HSEED/a.txt"; git -C "$HSEED" add -A
    git -C "$HSEED" commit -qm A >/dev/null 2>&1
    git -C "$HSEED" push -q "$HBARE" master:master >/dev/null 2>&1
    H_BEFORE=$(git -C "$HBARE" rev-parse master)
    # clone the bare into a beagle wt, commit a FF descendant locally, then push.
    rm -rf "$WORK/hwt"; mkdir "$WORK/hwt"
    ( cd "$WORK/hwt" && "$JABC" get "ssh://localhost/$HREL/host.git" ) \
        >"$WORK/hget.out" 2>"$WORK/hget.err" \
        || _fail "host-slot: ssh clone failed: $(cat "$WORK/hget.err")"
    ( cd "$WORK/hwt" && printf 'A\nB\n' > a.txt && "$JABC" put a.txt \
        && "$JABC" post '#hcommit' ) >"$WORK/hpost.out" 2>"$WORK/hpost.err" \
        || _fail "host-slot: local FF commit failed: $(cat "$WORK/hpost.err")"
    H_CUR=$(grep -aoE '#[0-9a-f]{40}' "$WORK/hwt/.be/wtlog" | tail -1 | tr -d '#')
    [ -n "$H_CUR" ] && [ "$H_CUR" != "$H_BEFORE" ] \
        || _fail "host-slot: local commit did not advance cur"
    ( cd "$WORK/hwt" && "$JABC" post "ssh://localhost/$HREL/host.git?master" ) \
        >"$WORK/hpush.out" 2>"$WORK/hpush.err" \
        || _fail "host-slot: wire push failed: $(cat "$WORK/hpush.err")"
    H_AFTER=$(git -C "$HBARE" rev-parse master)
    [ "$H_AFTER" = "$H_CUR" ] \
        || _fail "host-slot: ssh push did NOT FF-advance the bare to cur ($H_CUR; got $H_AFTER)"
    git -C "$HBARE" fsck >/dev/null 2>&1 || _fail "host-slot: pushed bare fails fsck"
else
    echo "SKIP [$NAME] host-slot ssh push (no git/ssh-localhost/\$HOME scratch)"
fi

# NEGATIVE (always runs): a bogus `//host` push must FAIL cleanly — non-zero,
# no POSTPUSH refuse, and the local store tip UNCHANGED (no silent commit).
_clone_staged hn
HN_T0=$(_tip "$WORK/hn")
if ( cd "$WORK/hn" && "$JABC" post "//host" ) >"$WORK/hn.out" 2>"$WORK/hn.err"; then
    _fail "post '//host' unexpectedly succeeded (silent local commit?): $(cat "$WORK/hn.out")"
fi
grep -q "POSTPUSH" "$WORK/hn.err" \
    && _fail "post '//host' refused via stale POSTPUSH — push is implemented now: $(cat "$WORK/hn.err")"
[ "$(_tip "$WORK/hn")" = "$HN_T0" ] \
    || _fail "post '//host' mutated the store tip (a failed push must not local-commit)"

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
( cd "$WORK/q2" && "$BE" get "file://$ORG/.be" >/dev/null 2>&1 )
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
( cd "$WORK/p1" && "$BE" get "file://$ORG2/.be" >/dev/null 2>&1 )
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
( cd "$WORK/p2" && "$BE" get "file://$ORG3/.be" >/dev/null 2>&1 )
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
