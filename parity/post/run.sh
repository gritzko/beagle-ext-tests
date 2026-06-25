#!/bin/sh
# JSQUE-012 parity case: `be post` via the resident loop — full-line byte
# parity, native `be post` vs `jab be/loop.js post` (SUT=loop).  POST is the
# COMMIT BARRIER verb: the handler runs the refuse pre-flight gate, then folds
# the staged change-set into one tree + commit via core/barrier.js, advances
# the ref, and prints the `post:` banner through ctx.out.
#
# Two legs:
#   1. a normal commit — a tracked mod + a new file + a delete + a kept file;
#      asserts the `post:` banner, the wtlog post rows, and the refs rows are
#      byte-identical.  The commit sha embeds the author/committer epoch (the
#      post-row stamp), so to make two independent posts byte-identical we PIN
#      the stamp (postcase.sh trick): an identical near-future seed row in each
#      fork's wtlog clamps both posts to `tail+1` — same ron60, same epoch,
#      same sha.  (Without the pin the trees/refs still match; the sha would
#      only differ if the two posts straddle a wall-clock second.)
#   2. a refuse — an empty post (no staged change) must POSTNONE on BOTH sides
#      (non-zero exit, no banner, store byte-intact).  Covers the pre-flight
#      gate parity.
#
# Default $SUT=oneshot gates today's post.js (still a one-shot in the landed
# tree); `SUT=loop` gates the JSQUE-012 handler — same case file, no edit.
. "$(dirname "$0")/../../lib/parity.sh"

# --- timestamp pin: append an identical near-future seed row to both wtlogs --
# (postcase.sh recipe) so ulog.nowAfter clamps both posts to the same stamp.
_mk_seed() {
    cat > "$WORK/.mkseed.js" <<'EOF'
const u=utf8.Encode(ron.of(Date.now()+3000).toString());
const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.mkseed.js" 2>/dev/null
}
_seed_wtlog() {   # _seed_wtlog WTDIR SEEDRON
    cat > "$WORK/.seed.js" <<'EOF'
// JSQUE-016: ulog/be moved to shared/ + core/discover; probe both layouts so
// this seed helper works for the flat (landed) AND by-verb (reorg) be/ shard.
function pick(d, a){ for(const p of a){ try{ if(io.stat(d+"/"+p).kind==="reg") return d+"/"+p; }catch(e){} } return d+"/"+a[0]; }
const D = process.argv[3];
const ulog = require(pick(D, ["shared/ulog.js","lib/ulog.js"]));
const be   = require(pick(D, ["core/discover.js","lib/be.js"]));
const info = be.find(process.argv[2]);
ulog.append(info.bePath, [{ verb:"mod", uri:"?/.seed", ts: BigInt(process.argv[4]) }]);
EOF
    "$JABC" "$WORK/.seed.js" "$1" "$BEDIR" "$2" 2>/dev/null
}

# post_parity ARGS… — run native `be post ARGS` in $NAT and the JS path (per
# $SUT) in $JS, both in-place, then assert stdout + wtlog post rows + refs rows.
# (verb_parity's twin; we pin the stamp first for sha determinism.)
post_parity() {
    SEED=$(_mk_seed)
    _seed_wtlog "$NAT" "$SEED"
    _seed_wtlog "$JS"  "$SEED"
    ( cd "$NAT" && run_native post "$@" ) >"$NAT.out" 2>"$NAT.err" || true
    ( cd "$JS"  && run_js     post "$@" ) >"$JS.out"  2>"$JS.err"  || true
    assert_stdout "$NAT.out" "$JS.out"
    assert_wtlog  "$NAT" "$JS" post
    assert_refs   "$NAT" "$JS"
}

# === leg 1: a normal commit (mod + new + del + kept), byte-parity =========
seed_baseline 'printf "A\n" > a.txt; printf "B\n" > b.txt; printf "KEEP\n" > keep.txt; mkdir d; printf "C\n" > d/c.txt'
fork_pair
mutate 'sleep 0.02; printf "A2\n" > a.txt; printf "NEW\n" > new.txt; mkdir -p g; printf "G\n" > g/g.txt; rm b.txt; be put a.txt new.txt g/g.txt >/dev/null 2>&1; be delete b.txt >/dev/null 2>&1'
post_parity '#mixed change-set'
echo "ok: commit-barrier post parity passes (mod+new+del+kept)"

# === leg 2: refuse — an empty post must POSTNONE on both sides ============
# A second post with nothing staged: the tree equals the new baseline, so both
# sides refuse POSTNONE (non-zero exit, no banner).  Asserts the refuse-gate
# parity (empty stdout on both, both non-zero).
( cd "$NAT" && run_native post '#noop' ) >"$NAT.out2" 2>"$NAT.err2" && _fail "native empty post did not refuse"
( cd "$JS"  && run_js     post '#noop' ) >"$JS.out2"  2>"$JS.err2"  && _fail "JS empty post did not refuse"
assert_stdout "$NAT.out2" "$JS.out2"
grep -q POSTNONE "$JS.err2" || _fail "JS empty post refused but not via POSTNONE: $(cat "$JS.err2")"
echo "ok: empty-post POSTNONE refuse parity passes"

pass
