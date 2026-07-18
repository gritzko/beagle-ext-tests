#!/bin/sh
# test/post/sub-diverged — POST-031: false parent-level verdicts minted in a
# SUB's shard.  Two live-incident faces (journal + be maintrees, 2026-07-18):
#
# Leg A (`post '?'` false non-FF): parent P's trunk is cur's clean ancestor
# (a textbook FF), but a mounted sub's STORE trunk genuinely diverged from
# the sub wt's cur.  postSubs recurses the parent's `?` bare-advance INTO the
# sub (ctx.args ride the fan-out), advanceBranch runs in the SUB's shard and
# its non-FF refusal bubbles up spelled as the PARENT's "`?` can not be
# fast-forwarded".  POST-030 already rules a recursed sub must not bare-
# advance its own track — enforced only for the no-Query form; the Query
# form (`?`) fell through.  The parent's own FF must proceed.
#
# Leg B (bare `status` false "broken tree"): a mounted sub was RE-CLONED from
# an unrelated store, so the parent's baseline gitlink pin (the STATUS-014
# track pin threaded into the sub's quad) names a commit ABSENT from the
# sub's store.  quadModel treats the dangling pin as a real tip, mergeBase
# finds no common ancestor, and the quad.js:146 throw kills the WHOLE status
# (and any :post that renders one).  A pin with no readable commit is NOT a
# real tip — the no-track degenerate rule applies (wiki/Status.mkd), the
# genuine two-real-tips broken-tree refusal stays (test/quad/model.js leg 3).
. "$(dirname "$0")/../../lib/postcase.sh"

# _subtip WT — the wt's cur tip (wtlog reader; works through .be redirects).
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

# _trunk WT — the wt's STORE trunk tip (store.resolveRef(''), the refs row).
_trunk() {
    cat > "$WORK/.trunk.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const info=be.treeAt(process.argv[2]);
const sha=store.open(info.storePath,info.project).resolveRef("")||"";
const u=utf8.Encode(sha+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.trunk.js" "$1" "$BEDIR" 2>/dev/null
}

# _pinrow SUBPATH WTLOG SHA — seed a `put <subpath>#<sha>` gitlink-bump row
# (the sub/nestedpost recipe — no CLI spelling for the first gitlink pin).
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

# ===== Leg A: parent `post '?'` over a genuinely diverged sub ================
# dog source store: c1, trunk minted at c1.
DOGSRC="$WORK/dogsrc"; mkdir -p "$DOGSRC/.be"
( cd "$DOGSRC" && printf 'dog v1\n' > DOG.c && "$BE" post '#dog c1' \
    && "$JABC" post '?' ) >/dev/null 2>&1 || _fail "dogsrc setup"
A0=$(_subtip "$DOGSRC"); _is40 "$A0" "dog tip A0"

# parent P: c1, trunk minted at c1 (so the leg's `?` advance is a real FF).
P="$WORK/P"; mkdir -p "$P/.be"
( cd "$P" && printf 'top v1\n' > TOP.c && "$BE" post '#parent c1' \
    && "$JABC" post '?' ) >/dev/null 2>&1 || _fail "parent P setup"
P0=$(_subtip "$P"); _is40 "$P0" "P tip P0"

# mount dog at A0 (redirect clone SHARING dogsrc's store) + commit the gitlink.
mkdir -p "$P/dog"
( cd "$P/dog" && "$BE" get "file://$DOGSRC/.be#$A0" ) >/dev/null 2>&1 \
    || _fail "mount dog"
[ -f "$P/dog/.be" ] || _fail "P/dog/.be not a FILE redirect"
_pinrow "dog" "$P/.be/wtlog" "$A0"
( cd "$P" && "$BE" post '#mount dog' ) >/dev/null 2>&1 \
    || _fail "commit dog gitlink"
P1=$(_subtip "$P"); _is40 "$P1" "P tip P1"

# diverge the dog store: the mounted wt commits B1 off A0; dogsrc commits A1
# off A0 and advances the SHARED store trunk to A1.  A1 vs B1 = a real fork.
( cd "$P/dog" && printf 'dog local\n' > DOG.c && "$BE" put DOG.c \
    && "$BE" post '#dog local' ) >/dev/null 2>&1 || _fail "sub local commit"
B1=$(_subtip "$P/dog"); _is40 "$B1" "dog tip B1"
( cd "$DOGSRC" && printf 'dog other\n' > DOG.c && "$BE" put DOG.c \
    && "$BE" post '#dog other' && "$JABC" post '?' ) >/dev/null 2>&1 \
    || _fail "dogsrc fork commit"
A1=$(_trunk "$DOGSRC"); _is40 "$A1" "dog trunk A1"
[ "$A1" != "$A0" ] || _fail "dog trunk did not advance"
[ "$A1" != "$B1" ] || _fail "fork collapsed (A1 == B1)"

# incident 1 dirty-wt leg: an uncommitted (unstaged) parent edit rides along.
printf 'top v1 dirty\n' > "$P/TOP.c"

# THE face: `post '?'` on P.  P's trunk P0 is cur P1's parent — a clean FF.
# RED today: the fan-out re-applies `?` in the DOG shard (trunk A1 vs cur B1,
# genuinely diverged) and its refusal aborts P's own advance.
RC=0
( cd "$P" && "$JABC" post '?' ) >"$WORK/adv.out" 2>"$WORK/adv.err" || RC=$?
grep -q "can not be fast-forwarded" "$WORK/adv.err" \
    && _fail "parent post ? refused non-FF (the sub shard's verdict): $(cat "$WORK/adv.err")"
[ "$RC" = 0 ] || _fail "parent post ? exit $RC: $(cat "$WORK/adv.err")"
PTR=$(_trunk "$P")
[ "$PTR" = "$P1" ] || _fail "P trunk is '$PTR', want cur $P1 (the FF advance)"
[ "$(_trunk "$DOGSRC")" = "$A1" ] || _fail "sub trunk moved — the fan-out advanced it"
[ "$(_subtip "$P/dog")" = "$B1" ] || _fail "sub cur moved on a bare parent advance"

# ===== Leg B: bare `status` over a re-cloned sub (dangling track pin) ========
S1="$WORK/s1"; mkdir -p "$S1/.be"
( cd "$S1" && printf 'sub v1\n' > SUB.c && "$BE" post '#s1 c1' ) \
    >/dev/null 2>&1 || _fail "s1 setup"
X0=$(_subtip "$S1"); _is40 "$X0" "s1 tip X0"
OTHER="$WORK/other"; mkdir -p "$OTHER/.be"
( cd "$OTHER" && printf 'other v1\n' > OTH.c && "$BE" post '#other c1' ) \
    >/dev/null 2>&1 || _fail "other setup"
Y0=$(_subtip "$OTHER"); _is40 "$Y0" "other tip Y0"

P2="$WORK/P2"; mkdir -p "$P2/.be"
( cd "$P2" && printf 'top2 v1\n' > TOP2.c && "$BE" post '#p2 c1' ) \
    >/dev/null 2>&1 || _fail "P2 setup"
mkdir -p "$P2/dog2"
( cd "$P2/dog2" && "$BE" get "file://$S1/.be#$X0" ) >/dev/null 2>&1 \
    || _fail "mount dog2"
_pinrow "dog2" "$P2/.be/wtlog" "$X0"
( cd "$P2" && "$BE" post '#mount dog2' ) >/dev/null 2>&1 \
    || _fail "commit dog2 gitlink"
# status recurses `.gitmodules` order — declare the sub like a real tree does.
printf '[submodule "dog2"]\n\tpath = dog2\n\turl = x\n' > "$P2/.gitmodules"

# RE-CLONE the sub wt from the UNRELATED store: the parent's pin X0 is now a
# dangling sha in the sub's shard (the live html re-clone shape, 2026-07-17).
rm -rf "$P2/dog2"; mkdir -p "$P2/dog2"
( cd "$P2/dog2" && "$BE" get "file://$OTHER/.be#$Y0" ) >/dev/null 2>&1 \
    || _fail "re-clone dog2 from other"

# THE face: bare `status` must RENDER (the dangling pin is no-track, not a
# broken tree).  RED today: quad.js throws "broken tree: track and base share
# no common ancestor" for the sub and the WHOLE status dies.
RC=0
( cd "$P2" && "$JABC" status ) >"$WORK/st.out" 2>"$WORK/st.err" || RC=$?
grep -q "broken tree" "$WORK/st.err" \
    && _fail "bare status threw broken-tree on the re-cloned sub: $(cat "$WORK/st.err")"
[ "$RC" = 0 ] || _fail "bare status exit $RC: $(cat "$WORK/st.err")"
grep -q "dog2" "$WORK/st.out" \
    || _fail "status rendered no dog2 rows: $(cat "$WORK/st.out")"

pass
