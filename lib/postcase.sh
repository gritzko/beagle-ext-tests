# test/js/lib/postcase.sh — differential parity harness for `bin/post.js`
# (the pure-JS `be post`, JS-051).  Sourced at the top of every
# test/js/post/<case>/run.sh.  Posts the SAME staged change-set with native
# `be post` AND `jabc bin/post.js`, then asserts byte-equivalence: the
# commit OBJECT (sha + bytes), the REFS row, the wtlog post row, and the
# `post:` banner.
#
# The commit sha embeds the author/committer epoch (the post-row stamp's
# wall-clock second).  To make two independent posts byte-identical we PIN
# the stamp: each side gets an identical NEAR-FUTURE (now+3s) seed row in its
# wtlog, so SNIFFAtNow / ulog.nowAfter both clamp the post to `tail+1` — the
# same ron60, hence the same epoch second, hence the same sha.  (now+3s stays
# under the 30s CLOCKBAD skew guard.)  Each side is an INDEPENDENT full clone
# of one post-c1 origin store, so the parent commit is identical too.
#
# Self-contained (does NOT source test/lib/case.sh — this case sits 3 levels
# deep at test/js/post/<case>).  POSIX sh.

set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)            # test/js/post/<case>
_ROOT=$(cd "$_CASE/../.." && pwd)          # repo root
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "postcase: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-$_BIN/jab}
# JAB-001: scripts live in the sibling `be/` submodule ($_ROOT/../be).
# GUARD: skip (exit 0) if that cross-submodule path is absent.
BEDIR="$_ROOT/.."
[ -f "$BEDIR/main.js" ] || { echo "postcase: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }
[ -x "$JABC" ] || { echo "postcase: no jab at $JABC" >&2; exit 2; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
export BE JABC BEDIR

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/js-post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sf "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
export WORK

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [$NAME]"; }

# strip the leading 7-col date so two runs at different wall-clocks compare.
_norm() { sed -E 's/^ *[0-9]{1,2}:[0-9]{2} */T /'; }

# --- timestamp pin: append an identical near-future seed row to a wtlog ----
# _seed_ron once per run (shared by both sides) → identical clamp.
_mk_seed() {
    cat > "$WORK/.mkseed.js" <<'EOF'
const u=utf8.Encode(ron.of(Date.now()+3000).toString());
const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.mkseed.js" 2>/dev/null
}
_seed_wtlog() {   # _seed_wtlog WTDIR SEEDRON
    cat > "$WORK/.seed.js" <<'EOF'
const ulog = require(process.argv[3] + "/shared/ulog.js");
const be   = require(process.argv[3] + "/core/discover.js");
const info = be.find(process.argv[2]);
ulog.append(info.bePath, [{ verb:"mod", uri:"?/.seed", ts: BigInt(process.argv[4]) }]);
EOF
    "$JABC" "$WORK/.seed.js" "$1" "$BEDIR" "$2" 2>/dev/null
}

# --- commit/refs probes (read a worktree's tip + commit bytes) -------------
_commit_dump() {  # _commit_dump WTDIR  → "tip=<sha>\n<commit bytes>"
    cat > "$WORK/.dump.js" <<'EOF'
const be    = require(process.argv[3] + "/core/discover.js");
const store = require(process.argv[3] + "/shared/store.js");
const info  = be.find(process.argv[2]);
const k = store.open(info.storePath, info.project);
const tip = k.resolveRef("");
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w("tip="+tip+"\n");
const c = k.getObject(tip);
if (c) io.write(1,(function(){const b=io.buf(c.bytes.length+8);b.feed(c.bytes);return b;})());
EOF
    "$JABC" "$WORK/.dump.js" "$1" "$BEDIR" 2>/dev/null
}

# Each clone is a PRIMARY full clone — its OWN store sits at
# `<side>/.be/<proj>/refs`, its wtlog at `<side>/.be/wtlog`.  Parity reads
# the CLONE's store, not the untouched source copy.
_refs_row() {   # _refs_row SIDE  → the LAST refs row, ts-normalised
    tail -1 "$WORK/$1/.be/org/refs" 2>/dev/null | sed -E 's/^[^\t]*\t/T\t/'
}
_wtlog_post_row() {   # last post row of a side's primary wtlog
    grep -a $'\tpost\t' "$WORK/$1/.be/wtlog" 2>/dev/null | tail -1 | sed -E 's/^[^\t]*\t/T\t/'
}

# --- post_parity: stage a change-set in two independent clones, post each --
# Usage:
#   post_parity ORIGIN_BUILDER STAGE_FN MSG
# where ORIGIN_BUILDER builds the c1 origin in $1 (a fresh primary repo),
# STAGE_FN edits+stages the change-set in $1 (run in each clone before post),
# MSG is the commit message (passed as `#MSG`).  Asserts commit/refs/wtlog/
# banner parity.  Leaves $WORK/nT and $WORK/jT for the caller.
post_parity() {
    _origin_builder=$1; _stage=$2; _msg=$3
    ORG="$WORK/org"; mkdir -p "$ORG"; ( cd "$ORG" && mkdir .be && "$_origin_builder" )
    # Each side gets its OWN store copy (a `.be`-shaped dir → an independent
    # redirected store), so the two posts never race the same refs.
    mkdir -p "$WORK/nstore.be" "$WORK/jstore.be"
    cp -a "$ORG/.be/." "$WORK/nstore.be/"; cp -a "$ORG/.be/." "$WORK/jstore.be/"
    mkdir "$WORK/nT" "$WORK/jT"
    #  URI-006 St.2: `file:` is worktree-only; the host-less `be:` local
    #  keeper wire (St.1) makes the independent own-store clone.
    ( cd "$WORK/nT" && "$BE" get "be:$WORK/nstore.be?/org" >/dev/null 2>&1 )
    ( cd "$WORK/jT" && "$BE" get "be:$WORK/jstore.be?/org" >/dev/null 2>&1 )
    SEED=$(_mk_seed)
    _seed_wtlog "$WORK/nT" "$SEED"
    _seed_wtlog "$WORK/jT" "$SEED"
    ( cd "$WORK/nT" && "$_stage" )
    ( cd "$WORK/jT" && "$_stage" )
    ( cd "$WORK/nT" && "$BE" post "#$_msg" ) >"$WORK/nT.out" 2>"$WORK/nT.err" || _fail "native post failed: $(cat "$WORK/nT.err")"
    ( cd "$WORK/jT" && "$JABC" post "#$_msg" ) >"$WORK/jT.out" 2>"$WORK/jT.err" || _fail "JS post failed: $(cat "$WORK/jT.err")"

    # banner
    _norm <"$WORK/nT.out" >"$WORK/nT.norm"; _norm <"$WORK/jT.out" >"$WORK/jT.norm"
    cmp -s "$WORK/nT.norm" "$WORK/jT.norm" || {
        echo "--- native banner ---"; cat "$WORK/nT.out"; echo "--- js banner ---"; cat "$WORK/jT.out"
        _fail "banner differs"; }
    # commit object (sha + bytes)
    _commit_dump "$WORK/nT" >"$WORK/nT.commit"; _commit_dump "$WORK/jT" >"$WORK/jT.commit"
    cmp -s "$WORK/nT.commit" "$WORK/jT.commit" || {
        echo "--- native commit ---"; cat "$WORK/nT.commit"; echo
        echo "--- js commit ---"; cat "$WORK/jT.commit"; echo
        _fail "commit object differs"; }
    # refs + wtlog rows
    [ "$(_refs_row nT)" = "$(_refs_row jT)" ] || _fail "refs row differs"
    [ "$(_wtlog_post_row nT)" = "$(_wtlog_post_row jT)" ] || _fail "wtlog post row differs"
    # native reads the JS-posted store clean
    _s=$( cd "$WORK/jT" && "$BE" status 2>/dev/null | tail -1 )
    case "$_s" in *ok*) ;; *) _fail "native be status on JS tree not clean: $_s" ;; esac
}
