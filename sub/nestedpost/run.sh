#!/bin/sh
# test/sub/nestedpost — SUBS-052: a selective top `post` must commit a staged
# change at ANY mount depth.  `be post` at the top of a selective wt gates each
# mounted sub by parent-scope rows, its own `adv` bucket, or anyStaged(that sub's
# OWN wtlog) — all single-level.  A change staged TWO mounts down (put-staged in
# the grandchild's wtlog, mid sub clean) left the mid sub out of scope, the
# recursion never started, and the top post committed only the top's files — no
# error.  The fix (post.js postSubs) makes the sub-scope test TRANSITIVE: a sub
# is in scope iff its own wtlog OR any descendant mounted sub's wtlog has staged
# rows, or any descendant is adv.  The post-order recursion then does the rest.
#
# JAB-only / keeper-free green-field recipe (reuses test/sub/nestedput's): the
# nested mounts are `jab get` clones into subdirs of the parent wt (each plants a
# `.be` FILE redirect), and each level's gitlink is seeded into the wtlog +
# committed so postSubs can enumerate it.  Asserts:
#   1. NESTED selective post: stage in the GRANDCHILD (from within it) + a TOP
#      file, top post → all three levels commit with correct gitlink bumps.
#   2. An unstaged-DIRTY grandchild (no `jab put`) under a clean mid stays
#      UNCOMMITTED (SUBS-042 selective semantics preserved).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/sub/nestedpost
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "nestedpost: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "nestedpost: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/sub/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the jsrc shard symlink (jab's upward jsrc-scan resolves the
# JS verbs from the worktree under test, above the /tmp fixtures).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export BE JABC BEDIR

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# --- jab probes (copied from test/sub/lib/subcase.sh) ------------------------
# _subtip WT — echo a wt's current cur tip (40-hex) via be.find + wtlog reader.
cat > "$WORK/.subtip.js" <<'EOF'
const be    = require(process.argv[3] + "/core/discover.js");
const wtlog = require(process.argv[3] + "/shared/wtlog.js");
const info  = be.treeAt(process.argv[2]);
const wtl = wtlog.open(info);
const cur = wtl.curTip();
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w((cur && cur.sha) || "");
EOF
_subtip() { "$JABC" "$WORK/.subtip.js" "$1" "$BEDIR" 2>/dev/null; }

# _pin WT SUBPATH — echo the 40-hex gitlink pin committed for SUBPATH in WT's
# baseline tree (reads the shard's tip tree).
cat > "$WORK/.pin.js" <<'EOF'
const be    = require(process.argv[3] + "/core/discover.js");
const store = require(process.argv[3] + "/shared/store.js");
const wtlog = require(process.argv[3] + "/shared/wtlog.js");
const info  = be.treeAt(process.argv[2]);
const k = store.open(info.storePath, info.project);
// DIS-076: a bare post never mints a ref — the worktree's own cur is the tip.
const tip = wtlog.open(info).curTip().sha;
let pin = "";
if (tip) {
  const tree = k.commitTree(tip);
  k.readTreeRecursive(tree, function (l) {
    if (l.kind === "s" && l.path === process.argv[4]) pin = l.sha;
  });
}
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w(pin);
EOF
_pin() { "$JABC" "$WORK/.pin.js" "$1" "$BEDIR" "$2" 2>/dev/null; }

# _pinrow SUBPATH WTLOG SHA — append a `put <subpath>#<sha>` gitlink-bump row to
# a wtlog via ulog.append; the next `jab post` folds it into a 160000 baseline
# entry (fold-decide's gitlink-add branch).  jab has no CLI spelling for a manual
# gitlink pin, so the first gitlink is seeded straight into the wtlog.
cat > "$WORK/.pinrow.js" <<'EOF'
const ulog = require(process.argv[2] + "/shared/ulog.js");
ulog.append(process.argv[4], [{ verb: "put",
  uri: URI.make(undefined, undefined, process.argv[3], undefined, process.argv[5]) }]);
EOF
_pinrow() { "$JABC" "$WORK/.pinrow.js" "$BEDIR" "$1" "$2" "$3" >/dev/null 2>&1 || true; }

_is40() {
    case "$1" in
        ????????????????????????????????????????) ;;
        *) _fail "$2: not 40-hex: '$1'" ;;
    esac
}

# --- build_tree ROOT — a 3-level nested-mount tree with committed gitlinks -----
# Green-field: storeI (inn) + storeM (mid) + P (parent) are project-less
# colocated primaries; inn is mounted+gitlinked into mid, mid into P.  Leaves the
# whole tree CLEAN (every pin == its sub's cur tip) at $ROOT/P.
build_tree() {
    _R="$1"
    mkdir -p "$_R/storeI/.be" "$_R/storeM/.be" "$_R/P/.be"
    ( cd "$_R/storeI" && printf 'inn payload v1\n' > INN.c && "$BE" post 'inn initial' ) \
        >/dev/null 2>&1 || _fail "storeI setup"
    ( cd "$_R/storeM" && printf 'mid payload v1\n' > MID.c && "$BE" post 'mid initial' ) \
        >/dev/null 2>&1 || _fail "storeM setup"
    ( cd "$_R/P" && printf 'top payload v1\n' > TOP.c && "$BE" post 'parent initial' ) \
        >/dev/null 2>&1 || _fail "P setup"

    # Mount mid inside P, then inn inside P/mid (double-slash file://).
    # DIS-076: a bare post never mints a ref, so an un-fragmented remote has no
    # trunk to resolve — pin each mount clone at the source store's own tip.
    mkdir -p "$_R/P/mid"
    _midtip=$(_subtip "$_R/storeM")
    ( cd "$_R/P/mid" && "$BE" get "file://$_R/storeM/.be#$_midtip" ) >"$_R/getmid.out" 2>&1 \
        || { cat "$_R/getmid.out"; _fail "mount mid"; }
    [ -f "$_R/P/mid/.be" ] || _fail "P/mid/.be not a FILE redirect (mid not mounted)"
    mkdir -p "$_R/P/mid/inn"
    _inntip=$(_subtip "$_R/storeI")
    ( cd "$_R/P/mid/inn" && "$BE" get "file://$_R/storeI/.be#$_inntip" ) >"$_R/getinn.out" 2>&1 \
        || { cat "$_R/getinn.out"; _fail "mount inn"; }
    [ -f "$_R/P/mid/inn/.be" ] || _fail "P/mid/inn/.be not a FILE redirect (inn not mounted)"

    # Commit the inn gitlink into mid: seed a `put inn#<inn-tip>` bump into mid's
    # wtlog (the P/mid/.be FILE), then post at the mid level.
    _t=$(_subtip "$_R/P/mid/inn"); _is40 "$_t" "inn tip (build)"
    _pinrow "inn" "$_R/P/mid/.be" "$_t"
    ( cd "$_R/P/mid" && "$BE" post 'mount inn' ) >"$_R/postmid.out" 2>&1 \
        || { cat "$_R/postmid.out"; _fail "commit inn gitlink"; }

    # Commit the mid gitlink into P: seed a `put mid#<mid-tip>` bump into P's
    # wtlog, then post at P.
    _t=$(_subtip "$_R/P/mid"); _is40 "$_t" "mid tip (build)"
    _pinrow "mid" "$_R/P/.be/wtlog" "$_t"
    ( cd "$_R/P" && "$BE" post 'mount mid' ) >"$_R/postp.out" 2>&1 \
        || { cat "$_R/postp.out"; _fail "commit mid gitlink"; }

    # Sanity: both gitlinks committed and pins match sub tips (clean tree).
    _pmid=$(_pin "$_R/P" "mid");             _is40 "$_pmid" "P.mid pin (build)"
    _pinn=$(_pin "$_R/P/mid" "inn");         _is40 "$_pinn" "mid.inn pin (build)"
    [ "$_pmid" = "$(_subtip "$_R/P/mid")" ]     || _fail "build: P.mid pin != mid tip"
    [ "$_pinn" = "$(_subtip "$_R/P/mid/inn")" ] || _fail "build: mid.inn pin != inn tip"
}

# ============================================================================
# 1. NESTED selective post: stage in the grandchild (from within it) + a TOP
#    file, top post → all three levels commit with correct gitlink bumps.
# ============================================================================
A="$WORK/a"; mkdir -p "$A"
build_tree "$A"
P="$A/P"

INN0=$(_subtip "$P/mid/inn"); MID0=$(_subtip "$P/mid"); TOP0=$(_subtip "$P")
_is40 "$INN0" "inn tip0"; _is40 "$MID0" "mid tip0"; _is40 "$TOP0" "top tip0"

# Stage a change TWO mounts down, FROM WITHIN the grandchild (independent of
# SUBS-051's put single-level descent).  Mid stays clean.
printf 'inn payload v2 EDITED\n' > "$P/mid/inn/INN.c"
( cd "$P/mid/inn" && "$BE" put INN.c ) >"$WORK/put_inn.out" 2>"$WORK/put_inn.err" \
    || { cat "$WORK/put_inn.err"; _fail "put INN.c in grandchild"; }
# Stage a TOP file → the top wt is SELECTIVE.
printf 'top payload v2 EDITED\n' > "$P/TOP.c"
( cd "$P" && "$BE" put TOP.c ) >"$WORK/put_top.out" 2>"$WORK/put_top.err" \
    || { cat "$WORK/put_top.err"; _fail "put TOP.c at top"; }

# The selective top post: the mid sub is CLEAN and not in the top's parent scope,
# so the SUBS-042 single-level gate skipped it and the grandchild never committed.
_rc=0
( cd "$P" && "$BE" post '#nested cascade' ) >"$WORK/post1.out" 2>"$WORK/post1.err" || _rc=$?
[ "$_rc" = 0 ] || { echo "--- out ---"; cat "$WORK/post1.out"; \
    echo "--- err ---"; cat "$WORK/post1.err"; _fail "nested top post exit $_rc"; }

INN1=$(_subtip "$P/mid/inn"); MID1=$(_subtip "$P/mid"); TOP1=$(_subtip "$P")
_is40 "$INN1" "inn tip1"; _is40 "$MID1" "mid tip1"; _is40 "$TOP1" "top tip1"

# The grandchild committed (SUBS-052 core: a staged change >=2 mounts down lands).
[ "$INN1" != "$INN0" ] || _fail "SUBS-052: grandchild (inn) did NOT commit — staged change 2 mounts down silently skipped"
# The mid child committed (a gitlink bump for inn's new tip).
[ "$MID1" != "$MID0" ] || _fail "SUBS-052: mid child did NOT commit the inn gitlink bump"
# The top committed (a gitlink bump for mid's new tip + the staged TOP file).
[ "$TOP1" != "$TOP0" ] || _fail "SUBS-052: top did NOT commit"
# Gitlink bumps are correct at each level.
[ "$(_pin "$P/mid" "inn")" = "$INN1" ] || _fail "mid.inn gitlink not bumped to inn's new tip"
[ "$(_pin "$P" "mid")" = "$MID1" ]     || _fail "P.mid gitlink not bumped to mid's new tip"
echo "ok   1. selective top post cascaded a grandchild-staged change through all 3 levels with correct gitlink bumps"

# ============================================================================
# 2. An unstaged-DIRTY grandchild (no `jab put`) under a clean mid, with only a
#    TOP file staged, stays UNCOMMITTED (SUBS-042 selective semantics).
# ============================================================================
B="$WORK/b"; mkdir -p "$B"
build_tree "$B"
Q="$B/P"

INN0=$(_subtip "$Q/mid/inn"); MID0=$(_subtip "$Q/mid")
PINN0=$(_pin "$Q/mid" "inn"); PMID0=$(_pin "$Q" "mid")

# Dirty the grandchild file but do NOT stage it; stage only a TOP file.
printf 'inn payload DIRTY-UNSTAGED\n' > "$Q/mid/inn/INN.c"
printf 'top payload v2 EDITED\n' > "$Q/TOP.c"
( cd "$Q" && "$BE" put TOP.c ) >"$WORK/put_top2.out" 2>"$WORK/put_top2.err" \
    || { cat "$WORK/put_top2.err"; _fail "put TOP.c (arm 2)"; }

_rc=0
( cd "$Q" && "$BE" post '#selective top only' ) >"$WORK/post2.out" 2>"$WORK/post2.err" || _rc=$?
[ "$_rc" = 0 ] || { echo "--- out ---"; cat "$WORK/post2.out"; \
    echo "--- err ---"; cat "$WORK/post2.err"; _fail "arm2 top post exit $_rc"; }

# The dirty-but-UNSTAGED grandchild is left at its tip; neither gitlink moved.
[ "$(_subtip "$Q/mid/inn")" = "$INN0" ] || _fail "arm2: unstaged-dirty grandchild COMMITTED (should be skipped)"
[ "$(_subtip "$Q/mid")" = "$MID0" ]     || _fail "arm2: mid child spuriously committed"
[ "$(_pin "$Q/mid" "inn")" = "$PINN0" ] || _fail "arm2: mid.inn gitlink spuriously bumped"
[ "$(_pin "$Q" "mid")" = "$PMID0" ]     || _fail "arm2: P.mid gitlink spuriously bumped"
echo "ok   2. unstaged-dirty grandchild stays uncommitted under a selective top (SUBS-042 semantics intact)"

echo "PASS [$NAME]"
