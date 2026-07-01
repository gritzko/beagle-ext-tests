# JAB-003 test/lib/postcase.sh — golden-snapshot harness for the hunk-emitting
# `be post` (jab).  post_parity now snapshots jab's OWN verified-correct output
# (no native `be post` oracle: native stays columnar while jab emits true hunks).
#
# Sourced at the top of every test/js/post/<case>/run.sh.  Posts a staged
# change-set with `jab post`, then folds the `post:` banner + wtlog post row +
# refs row + file set into ONE golden stream (see post_parity / lib/golden.sh).
#
# JAB-003 The commit sha embeds the wall-clock epoch, so it is VOLATILE run to
# run; the golden folds it (like the date column) — see post_parity.
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
. "$_ROOT/lib/golden.sh"                          # JAB-003: golden_assert
GOLDEN=${GOLDEN:-$_CASE/golden.out}               # JAB-003: committed snapshot
WORK="$TMP/$$/js-post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
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

# JAB-003 fold the VOLATILE commit sha (`?#<40hex>` in a row, `?<8hex>#` in the
# banner) to a stable token; golden_norm folds the date column too.
_postnorm() { sed -E 's/\?#[0-9a-f]{40}/?#SHA/; s/\?[0-9a-f]{7,40}#/?SHA#/'; }
_fileset() { ( cd "$1" && find . -type f | grep -vE '/\.be|^\./\.be' | sort ); }

# JAB-003 post_parity: build the c1 origin, clone into ONE JS tree, stage +
# `jab post`, then snapshot the `post:` banner + wtlog post row + refs row +
# file set as one golden stream.  No native `be post` oracle.
# Usage: post_parity ORIGIN_BUILDER STAGE_FN MSG (name kept for the call site;
# ORIGIN_BUILDER/STAGE_FN are the repo SETUP, MSG is the `#MSG` commit message).
post_parity() {
    _origin_builder=$1; _stage=$2; _msg=$3
    ORG="$WORK/org"; mkdir -p "$ORG"; ( cd "$ORG" && mkdir .be && "$_origin_builder" )
    # JAB-003 single JS-side own-store clone (native fork retired).
    mkdir -p "$WORK/jstore.be"; cp -a "$ORG/.be/." "$WORK/jstore.be/"
    mkdir "$WORK/jT"
    #  URI-006 St.2: `file:` is worktree-only; the host-less `be:` local
    #  keeper wire (St.1) makes the independent own-store clone.
    ( cd "$WORK/jT" && "$BE" get "be:$WORK/jstore.be?/org" >/dev/null 2>&1 )
    SEED=$(_mk_seed)
    _seed_wtlog "$WORK/jT" "$SEED"
    ( cd "$WORK/jT" && "$_stage" )
    ( cd "$WORK/jT" && "$JABC" post "#$_msg" ) >"$WORK/jT.out" 2>"$WORK/jT.err" || _fail "JS post failed: $(cat "$WORK/jT.err")"

    # JAB-003 fold banner + wtlog post row + refs row + file set into ONE golden.
    {
        echo "=== stdout ==="; cat "$WORK/jT.out"
        echo "=== wtlog post row ==="; _wtlog_post_row jT
        echo "=== refs row ==="; _refs_row jT
        echo "=== file set ==="; _fileset "$WORK/jT"
    } | _postnorm | golden_assert "$NAME" "$GOLDEN"
}
