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
# TEST-003: jab-only — native `be` is RETIRED (it now LAGS jab).  Locate jab and
# alias BE=$JABC so every legacy `"$BE"` seed/clone in a case seeds with jab too.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "postcase: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
# JAB-001: scripts live in the sibling `be/` submodule ($_ROOT/../be).
# GUARD: skip (exit 0) if that cross-submodule path is absent.
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "postcase: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

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
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
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
const info = be.treeAt(process.argv[2]);
ulog.append(info.bePath, [{ verb:"mod", uri:"?/.seed", ts: BigInt(process.argv[4]) }]);
EOF
    "$JABC" "$WORK/.seed.js" "$1" "$BEDIR" "$2" 2>/dev/null
}

# --- commit/refs probes (read a worktree's tip + commit bytes) -------------
_commit_dump() {  # _commit_dump WTDIR  → "tip=<sha>\n<commit bytes>"
    cat > "$WORK/.dump.js" <<'EOF'
const be    = require(process.argv[3] + "/core/discover.js");
const store = require(process.argv[3] + "/shared/store.js");
const info  = be.treeAt(process.argv[2]);
const k = store.open(info.storePath, info.project);
const tip = k.resolveRef("");
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w("tip="+tip+"\n");
const c = k.getObject(tip);
if (c) io.write(1,(function(){const b=io.buf(c.bytes.length+8);b.feed(c.bytes);return b;})());
EOF
    "$JABC" "$WORK/.dump.js" "$1" "$BEDIR" 2>/dev/null
}

# TEST-003: a jab `file://` clone is a SECONDARY wt whose `<side>/.be` is a
# REDIRECT FILE (itself the wtlog); its refs live in the redirect TARGET store's
# flat `<target>/refs` (jab is unnamed-project, so no `<proj>/refs`).  Follow the
# row-0 `get file:<target>/.be/?...` redirect to that target.
_redirect_be() {   # _redirect_be SIDE → the redirect target `.be` dir (or "")
    head -1 "$WORK/$1/.be" 2>/dev/null \
      | sed -nE 's#.*[[:space:]]file:([^?[:space:]]+/\.be)/?.*#\1#p'
}
_refs_row() {   # _refs_row SIDE  → the LAST refs row of the target store, ts-normalised
    _tgt=$(_redirect_be "$1")
    tail -1 "${_tgt:-$WORK/$1/.be}/refs" 2>/dev/null | sed -E 's/^[^\t]*\t/T\t/'
}
_wtlog_post_row() {   # last post row of a side's wtlog (the `.be` redirect FILE)
    grep -a $'\tpost\t' "$WORK/$1/.be" 2>/dev/null | tail -1 | sed -E 's/^[^\t]*\t/T\t/'
}

# JAB-003 fold the VOLATILE commit sha (`?#<40hex>` in a row, `?<8hex>#` in the
# banner) to a stable token; golden_norm folds the date column too.
_postnorm() { sed -E 's/\?#[0-9a-f]{40}/?#SHA/; s/\?[0-9a-f]{7,40}#/?SHA#/'; }
# TEST-003: drop the `.be` redirect FILE and jab's sibling `..be.idx` index.
_fileset() { ( cd "$1" && find . -type f | grep -vE '/\.be|^\./\.be|/\.\.be\.idx|^\./\.\.be\.idx' | sort ); }

# JAB-003 post_parity: build the c1 origin, clone into ONE JS tree, stage +
# `jab post`, then snapshot the `post:` banner + wtlog post row + refs row +
# file set as one golden stream.  No native `be post` oracle.
# Usage: post_parity ORIGIN_BUILDER STAGE_FN MSG (name kept for the call site;
# ORIGIN_BUILDER/STAGE_FN are the repo SETUP, MSG is the `#MSG` commit message).
post_parity() {
    _origin_builder=$1; _stage=$2; _msg=$3
    ORG="$WORK/org"; mkdir -p "$ORG"; ( cd "$ORG" && mkdir .be && "$_origin_builder" )
    # TEST-003: independent own-store clone.  The copied store dir MUST be named
    # `.be` (jab requires the store basename == `.be`), so copy into `jsrc/.be`.
    mkdir -p "$WORK/jsrc/.be"; cp -a "$ORG/.be/." "$WORK/jsrc/.be/"
    mkdir "$WORK/jT"
    # TEST-003: jab-seeded stores are UNNAMED-project single shards, so clone
    # via bare `file://<store>/.be` (no `?/org` selector — that selects a named
    # shard jab never creates); `be:` wire needs a retired native keeper.
    ( cd "$WORK/jT" && "$BE" get "file://$WORK/jsrc/.be" >/dev/null 2>&1 ) \
        || _fail "JS clone failed"
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
