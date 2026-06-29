# test/sub/lib/subcase.sh — DIS-058 (D1-D9) submodule get/post RECURSION
# repro harness.  Sourced at the top of every test/sub/<case>/run.sh.  Drives
# the JS loop (`jab get`/`jab post`) over a PURE local `be:` keeper-wire cycle
# (no git, no network): a parent store with a committed gitlink + a `.gitmodules`
# blob, cloned with the child fetched from the SAME source and mounted as a
# secondary worktree, edited, posted post-order, then re-cloned.
#
# Asserts the SPEC ([Submodules] Recursion), NOT native parity — the C `be`
# sub-cycle is a separate concern; here we gate the JS port's own recursion.
# POSIX sh.

set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)            # test/sub/<case>
_ROOT=$(cd "$_CASE/../.." && pwd)               # be/ repo root
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "subcase: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-$_BIN/jab}
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "subcase: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }
[ -x "$JABC" ] || { echo "subcase: no jab at $JABC" >&2; exit 2; }

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
: > "$TMP/$$/.be" 2>/dev/null || true
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sf "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
export WORK

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [$NAME]"; }

# sc_tip STORE PROJ — echo the full 40-hex CURRENT trunk tip of a shard's refs
# (the last `#<40hex>` in <STORE>/.be/<PROJ>/refs).
sc_tip() {
    od -An -c "$1/.be/$2/refs" 2>/dev/null \
        | tr -d ' \n' | grep -oE '#[0-9a-f]{40}' | tail -1 | tr -d '#'
}

# sc_subtip WT — echo a MOUNTED sub worktree's current cur tip via be.find +
# the store reader (the sub is a SECONDARY wt: its `.be` is a FILE redirect,
# so its shard refs live in the PARENT store, not <WT>/.be/<proj>/refs).
sc_subtip() {
    cat > "$WORK/.subtip.js" <<'EOF'
const be    = require(process.argv[3] + "/core/discover.js");
const wtlog = require(process.argv[3] + "/shared/wtlog.js");
const info  = be.find(process.argv[2]);
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
const info  = be.find(process.argv[2]);
const k = store.open(info.storePath, info.project);
const tip = k.resolveRef("");
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

# sc_build_parent — build, under $WORK, an isolated SUB store + a PARENT store
# that COMMITS the sub as a gitlink at <subpath> with a `.gitmodules` blob whose
# url is the sub's `be:` source.  Both are PRIMARY `be` stores clonable over the
# local keeper wire.  Sets globals: SUBSTORE, PARSTORE, SUBPROJ, PARPROJ,
# SUBPATH, SUBTIP0, PARTIP0.
sc_build_parent() {
    # The store-dir basename IS the project shard title ([Title] / native's
    # bootstrap rule), so name the dirs `sub`/`par` (matching the `.gitmodules`
    # url basename) — the spec's "[Title] from the .gitmodules URL basename".
    SUBSTORE="$WORK/sub"
    PARSTORE="$WORK/par"
    SUBPROJ="sub"
    PARPROJ="par"
    SUBPATH="vendor/sub"
    rm -rf "$SUBSTORE" "$PARSTORE"
    mkdir -p "$SUBSTORE/.be" "$PARSTORE/.be"

    # sub store: two tracked files, one commit (project "sub").
    ( cd "$SUBSTORE"
      printf 'sub payload v1\n' > lib.c
      printf 'sub helper\n'     > helper.c
      "$BE" post '#sub initial' >/dev/null 2>&1 ) || _fail "sub setup"
    SUBTIP0=$(sc_tip "$SUBSTORE" "$SUBPROJ")
    sc_is40 "$SUBTIP0" "sub tip0"

    # parent store: main.c baseline.
    ( cd "$PARSTORE"
      printf 'int main(void){return 0;}\n' > main.c
      "$BE" post '#parent main' >/dev/null 2>&1 ) || _fail "parent setup"

    # Mount + COMMIT the sub gitlink: .gitmodules (be: url, basename → project
    # "sub" per [Title]) + the secondary-wt `.be` anchor + the checked-out sub
    # files, then stage + post so the 160000 gitlink lands in the baseline tree.
    ( cd "$PARSTORE"
      cat > .gitmodules <<EOF
[submodule "vendor/sub"]
	path = vendor/sub
	url = be:$SUBSTORE/.be?/sub
EOF
      mkdir -p vendor/sub
      _r=$(awk -F'\t' 'NR==1{print $1; exit}' .be/wtlog)
      printf '%s\tget\tfile:%s/.be/?/sub#%s\n' "$_r" "$SUBSTORE" "$SUBTIP0" \
          > vendor/sub/.be
      printf 'sub payload v1\n' > vendor/sub/lib.c
      printf 'sub helper\n'     > vendor/sub/helper.c
      "$BE" put .gitmodules >/dev/null 2>&1
      "$BE" put vendor/sub  >/dev/null 2>&1
      "$BE" post '#mount sub' >/dev/null 2>&1 ) || _fail "mount sub"
    PARTIP0=$(sc_tip "$PARSTORE" "$PARPROJ")
    sc_is40 "$PARTIP0" "par tip0"
    grep -qE 'put[[:space:]]+vendor/sub#[0-9a-f]{40}' "$PARSTORE/.be/wtlog" \
        || _fail "gitlink not committed: $(cat "$PARSTORE/.be/wtlog")"
}

# sc_jget DST REMOTE — JS-clone REMOTE into the (made) DST dir; stdout->last.out
# stderr->last.err; echoes the exit code (never aborts under set -e).
sc_jget() {
    mkdir -p "$1"
    _rc=0
    ( cd "$1" && "$JABC" get "$2" ) >"$WORK/last.out" 2>"$WORK/last.err" || _rc=$?
    printf '%s\n' "$_rc"
}
