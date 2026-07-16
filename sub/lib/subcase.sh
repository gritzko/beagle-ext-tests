# test/sub/lib/subcase.sh — DIS-058 (D1-D9) submodule get/post RECURSION
# repro harness.  Sourced at the top of every test/sub/<case>/run.sh.  Drives
# the JS loop (`jab get`/`jab post`) over a parent store with a committed gitlink
# + a `.gitmodules` blob, cloned with the child fetched + mounted as a secondary
# worktree, edited, posted post-order, then re-cloned.
#
# TEST-003: the non-recursion consumers (symlink/selfloop/wtsrc + type/change)
# clone a single project-less colocated primary over `file://` — NO keeper.  The
# sub-RECURSION consumers (cycle/patch/selective/untracked/bare*{,-nested}) call
# sc_build_parent: those FLAGGED cases need the JS-keeper feature — a mounted
# submodule's CHILD is FETCHED at mount time through the git/keeper WIRE
# (submount.mount → wire.fetch), and jab is a wire CLIENT with no keeper-free
# LOCAL child-fetch (a sibling sub shard can't coexist with jab's project-less
# colocated primary — the empty-project auto-detect would pick the sub shard).
# So sc_build_parent commits the gitlink project-less-correctly, but the sub
# MOUNT on clone (and any re-clone of a modified beagle store) still spawns the
# retired keeper — that residual is the JS-keeper feature, out of this pass.
#
# Asserts the SPEC ([Submodules] Recursion), NOT native parity.  POSIX sh.

set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)            # test/sub/<case>
_ROOT=$(cd "$_CASE/../.." && pwd)               # be/ repo root
# TEST-003: jab-only — native `be` is RETIRED (it now LAGS jab), so the whole
# harness runs on jab: locate jab, and alias BE=$JABC so any legacy `"$BE"` seed
# call (sc_build_parent's `"$BE" post`) seeds with jab too.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "subcase: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "subcase: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

# wire transport env (be: spawns the local `keeper upload-pack`).
: "${KEEPER_BIN:=$_BIN/keeper}"
: "${DOG_REMOTE_PATH:=$_BIN}"
export BE JABC KEEPER_BIN DOG_REMOTE_PATH BEDIR
case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/js-sub/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export WORK

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [$NAME]"; }

# sc_tip STORE [PROJ] — echo STORE's own CURRENT worktree tip (wtlog cur).
# DIS-076: a bare post never moves a store ref, so the worktree's own cur
# (same reader as sc_subtip) is the only tip there is; PROJ ignored (legacy).
sc_tip() {
    cat > "$WORK/.tip.js" <<'EOF'
const be    = require(process.argv[3] + "/core/discover.js");
const wtlog = require(process.argv[3] + "/shared/wtlog.js");
const info  = be.treeAt(process.argv[2]);
const cur = wtlog.open(info).curTip();
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w((cur && cur.sha) || "");
EOF
    "$JABC" "$WORK/.tip.js" "$1" "$BEDIR" 2>/dev/null
}

# sc_subtip WT — echo a MOUNTED sub worktree's current cur tip via be.find +
# the store reader (the sub is a SECONDARY wt: its `.be` is a FILE redirect,
# so its shard refs live in the PARENT store, not <WT>/.be/<proj>/refs).
sc_subtip() {
    cat > "$WORK/.subtip.js" <<'EOF'
const be    = require(process.argv[3] + "/core/discover.js");
const wtlog = require(process.argv[3] + "/shared/wtlog.js");
const info  = be.treeAt(process.argv[2]);
const wtl = wtlog.open(info);
const cur = wtl.curTip();
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w((cur && cur.sha) || "");
EOF
    "$JABC" "$WORK/.subtip.js" "$1" "$BEDIR" 2>/dev/null
}

# sc_gitlink_pin WT PATH — echo the 40-hex gitlink pin committed for PATH in
# WT's baseline tree, by reading the parent shard's tip tree via a jab probe.
# Usage: sc_gitlink_pin <wt> <subpath>
sc_gitlink_pin() {
    cat > "$WORK/.pin.js" <<'EOF'
const be    = require(process.argv[3] + "/core/discover.js");
const store = require(process.argv[3] + "/shared/store.js");
const wtlog = require(process.argv[3] + "/shared/wtlog.js");
const info  = be.treeAt(process.argv[2]);
// DIS-076: a bare post never moves a store ref — WT's own cur is the tip.
const tip = wtlog.open(info).curTip().sha;
const k = store.open(info.storePath, info.project);
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
    "$JABC" "$WORK/.pin.js" "$1" "$BEDIR" "$2" 2>/dev/null
}

# sc_is40 VALUE LABEL — assert VALUE is a 40-hex sha, else fail with LABEL.
sc_is40() {
    case "$1" in
        ????????????????????????????????????????) ;;
        *) _fail "$2: not 40-hex: '$1'" ;;
    esac
}

# sc_pin_gitlink SUBPATH WTLOG SHA — TEST-003: append a `put <subpath>#<sha>`
# gitlink-bump row to a wtlog via ulog.append (proper monotonic stamp).  jab has
# no CLI spelling for a manual gitlink pin (`jab put a/b#sha` is a MOVE dest), so
# the first gitlink is seeded straight into the wtlog; the next `jab post` folds
# it into a 160000 baseline entry (fold-decide's gitlink-add branch).
sc_pin_gitlink() {
    cat > "$WORK/.pinrow.js" <<'EOF'
const ulog = require(process.argv[2] + "/shared/ulog.js");
ulog.append(process.argv[4], [{ verb: "put",
  uri: URI.make(undefined, undefined, process.argv[3], undefined, process.argv[5]) }]);
EOF
    "$JABC" "$WORK/.pinrow.js" "$BEDIR" "$1" "$2" "$3" >/dev/null 2>&1 || true
}

# sc_build_parent — build, under $WORK, an isolated SUB store + a PARENT store
# that COMMITS the sub as a gitlink at <subpath> with a `.gitmodules` blob whose
# url is the sub's `file://` source.  Both are project-less colocated primary
# jab stores.  Sets globals: SUBSTORE, PARSTORE, SUBPROJ, PARPROJ, SUBPATH,
# SUBTIP0, PARTIP0.
# TEST-003 FLAGGED: cloning the parent MOUNTS the sub, and the sub CHILD fetch
# runs through the git/keeper WIRE (submount.mount → wire.fetch) — there is no
# keeper-free LOCAL child-fetch in jab's project-less model, so the consuming
# recursion cases need the JS-keeper feature (out of this pass).
sc_build_parent() {
    SUBSTORE="$WORK/sub"
    PARSTORE="$WORK/par"
    SUBPROJ="sub"
    PARPROJ="par"
    SUBPATH="vendor/sub"
    rm -rf "$SUBSTORE" "$PARSTORE"
    mkdir -p "$SUBSTORE/.be" "$PARSTORE/.be"

    # sub store: two tracked files, one commit (project-less colocated primary).
    ( cd "$SUBSTORE"
      printf 'sub payload v1\n' > lib.c
      printf 'sub helper\n'     > helper.c
      "$BE" post '#sub initial' >/dev/null 2>&1 ) || _fail "sub setup"
    SUBTIP0=$(sc_tip "$SUBSTORE")
    sc_is40 "$SUBTIP0" "sub tip0"

    # parent store: main.c baseline.
    ( cd "$PARSTORE"
      printf 'int main(void){return 0;}\n' > main.c
      "$BE" post '#parent main' >/dev/null 2>&1 ) || _fail "parent setup"

    # Mount + COMMIT the sub gitlink: .gitmodules (file:// url, `?/sub` selector →
    # [Title] "sub") + the secondary-wt `.be` anchor (project-less redirect) + the
    # checked-out sub files, seed the gitlink pin row, then post so the 160000
    # gitlink lands in the baseline tree.
    ( cd "$PARSTORE"
      cat > .gitmodules <<EOF
[submodule "vendor/sub"]
	path = vendor/sub
	url = file://$SUBSTORE/.be?/sub
EOF
      mkdir -p vendor/sub
      _r=$(awk -F'\t' 'NR==1{print $1; exit}' .be/wtlog)
      printf '%s\tget\tfile:%s/.be/?/#%s\n' "$_r" "$SUBSTORE" "$SUBTIP0" \
          > vendor/sub/.be
      printf 'sub payload v1\n' > vendor/sub/lib.c
      printf 'sub helper\n'     > vendor/sub/helper.c
      "$BE" put .gitmodules >/dev/null 2>&1 ) || _fail "mount sub (put)"
    sc_pin_gitlink "$SUBPATH" "$PARSTORE/.be/wtlog" "$SUBTIP0"
    ( cd "$PARSTORE" && "$BE" post '#mount sub' >/dev/null 2>&1 ) || _fail "mount sub (post)"
    PARTIP0=$(sc_tip "$PARSTORE")
    sc_is40 "$PARTIP0" "par tip0"
    grep -qE 'put[[:space:]]+vendor/sub#[0-9a-f]{40}' "$PARSTORE/.be/wtlog" \
        || _fail "gitlink not committed: $(cat "$PARSTORE/.be/wtlog")"
}

# sc_jget DST REMOTE — JS-clone REMOTE into the (made) DST dir; stdout->last.out
# stderr->last.err; echoes the exit code (never aborts under set -e).
# DIS-076: a bare post never mints a ref, so an un-fragmented REMOTE has no
# trunk to resolve — pin it at the referenced tree's own cur (sc_tip),
# mirroring the get-harness `gr_jclone` fix.  Already-pinned (`#sha`) REMOTEs
# pass through unchanged; an unresolvable REMOTE (e.g. a deliberately broken
# fixture) also passes through unchanged, preserving its own failure mode.
sc_jget() {
    mkdir -p "$1"
    _remote=$2
    case "$_remote" in
        *'#'*) ;;
        *) _path=${_remote#file://}; _path=${_path#file:}
           _path=${_path%%\?*}; _path=${_path%/.be}
           _tip=$(sc_tip "$_path" 2>/dev/null)
           case "$_tip" in
               ????????????????????????????????????????) _remote="${_remote}#${_tip}" ;;
           esac ;;
    esac
    _rc=0
    ( cd "$1" && "$JABC" get "$_remote" ) >"$WORK/last.out" 2>"$WORK/last.err" || _rc=$?
    printf '%s\n' "$_rc"
}
