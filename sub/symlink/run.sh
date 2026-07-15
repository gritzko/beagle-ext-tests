#!/bin/sh
# test/sub/symlink — GET-039: a `120000` symlink round-trips as a BLOB through
# commit -> checkout, byte-identical to git's model.  A symlink IS a blob whose
# bytes are the link target verbatim (hashed via lstat+readlink, NEVER followed);
# its tree mode is `120000`; it is a LEAF, never a submodule.
#
# Commit `link -> some/target` (a relative target) in a `file://` store, `jab
# get` it, and assert: (a) the checked-out `link` is a SYMLINK whose readlink ==
# the committed target verbatim, and (b) the committed tree entry is mode
# `120000` kind `l` (a blob), NEVER a `160000` gitlink / mount.
#
# RED before GET-039's symlink-leaf path; green after.
# TEST-003: local project-less `file://` clone (no keeper); no submodule mount.
. "$(dirname "$0")/../lib/subcase.sh"

SLSTORE="$WORK/proj"
SLPROJ="proj"
TARGET="some/target"
rm -rf "$SLSTORE"
mkdir -p "$SLSTORE/.be"

# --- commit a symlink blob (`link -> some/target`) + a regular file ----------
( cd "$SLSTORE"
  printf 'regular payload\n' > main.c
  ln -s "$TARGET" link
  "$BE" post '#proj with symlink' >/dev/null 2>&1 ) || _fail "proj setup"
TIP=$(sc_tip "$SLSTORE" "$SLPROJ")
sc_is40 "$TIP" "proj tip"

# the committed `link` tree entry is a `120000` blob (kind l), NEVER a gitlink.
cat > "$WORK/.mode.js" <<'EOF'
const be    = require(process.argv[3] + "/core/discover.js");
const store = require(process.argv[3] + "/shared/store.js");
const info  = be.treeAt(process.argv[2]);
const k = store.open(info.storePath, info.project);
const tip = k.resolveRef("");
const tree = k.commitTree(tip);
let mode = "", kind = "";
k.readTreeRecursive(tree, function (l) {
  if (l.path === "link") { mode = (l.mode || 0).toString(8); kind = l.kind; }
});
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+16);b.feed(u);io.write(1,b);}
w(mode + " " + kind);
EOF
_modekind=$("$JABC" "$WORK/.mode.js" "$SLSTORE" "$BEDIR" 2>/dev/null)
[ "$_modekind" = "120000 l" ] \
    || _fail "committed \`link\` is [$_modekind] != [120000 l] (a symlink is a 120000 BLOB, not a gitlink)"

# ============================================================================
# GET: clone the project — the symlink must materialise via the generic leaf
# path (io.symlink), readlink-identical to the committed target.
# ============================================================================
T1="$WORK/get1"
_rc=$(sc_jget "$T1" "file://$SLSTORE/.be")
[ "$_rc" = 0 ] || { echo "--- get1 err ---"; cat "$WORK/last.err"; _fail "get1 exit $_rc"; }

[ -L "$T1/link" ] || _fail "get1: \`link\` is not a symlink (a 120000 blob must check out via io.symlink)"
_tgt=$(readlink "$T1/link")
[ "$_tgt" = "$TARGET" ] || _fail "get1: readlink \`link\` [$_tgt] != committed target [$TARGET]"
[ -f "$T1/main.c" ] || _fail "get1: main.c missing — checkout incomplete"

# NO stray `?/link` sub shard was fetched (a symlink is never a submodule).
[ -e "$SLSTORE/.be/link" ] && _fail "get1: a stray \`link\` sub shard was fetched (a symlink must never sub-mount)"

echo "ok   symlink \`link -> $TARGET\` round-trips as a 120000 blob (readlink-identical)"
pass
