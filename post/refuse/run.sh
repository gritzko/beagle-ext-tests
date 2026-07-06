#!/bin/sh
# test/js/post/refuse — `bin/post.js` refuse paths (JS-051 FF-or-refuse):
#   * empty-commit   → POSTNONE  (no store write, non-zero exit)
#   * non-FF advance → POSTNOFF  (the branch tip moved past our parent)
# Each refusal must leave the store byte-intact (the post is all-or-nothing).
. "$(dirname "$0")/../../lib/postcase.sh"

# store tip sha of a clone (via store.js, the same reader post.js uses).
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

# Origin store: post c1.
ORG="$WORK/org"; mkdir -p "$ORG"; ( cd "$ORG" && mkdir .be && {
    printf 'A\n' > a.txt; printf 'B\n' > b.txt
    "$BE" post '#c1' >/dev/null 2>&1
} )

# --- empty commit: a clean clone with no staged change must POSTNONE -------
# TEST-003: jab-seeded store is unnamed-project, so clone bare `file://<store>`
# (no `?/org` selector — jab never mints a named `org` shard).
mkdir "$WORK/e"; ( cd "$WORK/e" && "$BE" get "file://$ORG/.be" >/dev/null 2>&1 )
E_TIP0=$(_tip "$WORK/e")
if ( cd "$WORK/e" && "$JABC" post '#noop' ) >"$WORK/e.out" 2>"$WORK/e.err"; then
    _fail "empty post did NOT refuse (expected POSTNONE): $(cat "$WORK/e.out")"
fi
grep -q POSTNONE "$WORK/e.err" || _fail "empty post refused but not via POSTNONE: $(cat "$WORK/e.err")"
[ "$(_tip "$WORK/e")" = "$E_TIP0" ] || _fail "empty post mutated the store tip"

# --- non-FF: a sibling redirect clone advances the SHARED store, leaving us
#     parented at the stale tip → our JS post must POSTNOFF, no write. --------
# clone X (redirect → origin store), then a sibling redirect Y of X's store;
# Y posts, advancing the shared origin store past X's c1 parent.
mkdir "$WORK/x"; ( cd "$WORK/x" && "$BE" get "file://$ORG/.be" >/dev/null 2>&1 )
mkdir "$WORK/y"; ( cd "$WORK/y" && "$BE" get "file://$ORG/.be" >/dev/null 2>&1 )
( cd "$WORK/y" && printf 'A2\n' > a.txt && "$BE" put a.txt >/dev/null 2>&1 && "$BE" post '#adv' >/dev/null 2>&1 )
# the shared origin store tip is now y's commit; x's wtlog parent is still c1.
X_TIP_BEFORE=$(_tip "$WORK/x")
if ( cd "$WORK/x" && printf 'A3\n' > a.txt && "$BE" put a.txt >/dev/null 2>&1 && \
     "$JABC" post '#stale' ) >"$WORK/x.out" 2>"$WORK/x.err"; then
    _fail "non-FF post did NOT refuse (expected POSTNOFF): $(cat "$WORK/x.out")"
fi
grep -q POSTNOFF "$WORK/x.err" || _fail "non-FF post refused but not via POSTNOFF: $(cat "$WORK/x.err")"
[ "$(_tip "$WORK/x")" = "$X_TIP_BEFORE" ] || _fail "non-FF post mutated the store tip"

pass
