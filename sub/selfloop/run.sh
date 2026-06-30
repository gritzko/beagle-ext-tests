#!/bin/sh
# test/sub/selfloop — GET-039: the `be` self-locator committed as git's MODEL
# (a `120000` symlink `be -> .`), NOT a `160000` gitlink.  Under git's model a
# symlink is a blob — a LEAF, never followed during a walk, never a submodule —
# so `be -> .` is an ordinary `120000` leaf and ALL the `be`-name special-casing
# (get.js isSelfLocator + submount.mount refusal) dissolves.
#
# Asserts: (1) the recursive wt walk NEVER descends the `be -> .` self-link
# (no `be/be/be/...` blowup) — io.readdir(recursive) is no-follow; (2) `be` is
# a `120000` blob in the committed tree, NEVER a `160000` mount; (3) `jab get`
# materialises `be -> .` via the generic symlink leaf, checkout completes, and
# NO `?/be` sub shard is ever fetched.
#
# RED before GET-039's symlink-leaf path (the legacy 160000 self-gitlink lives
# in sub/selflink — GET-037; this is the git-model 120000 form GET-039 adopts).
# Pure local `be:` keeper wire — CI-friendly.
. "$(dirname "$0")/../lib/subcase.sh"

SLSTORE="$WORK/proj"
SLPROJ="proj"
rm -rf "$SLSTORE"
mkdir -p "$SLSTORE/.be"

# --- commit a `be -> .` self-locator as a 120000 SYMLINK (git's model) -------
( cd "$SLSTORE"
  printf 'hello from proj\n' > main.c
  printf 'extra payload\n'   > lib.c
  ln -s . be
  "$BE" post '#proj with be -> . self-link' >/dev/null 2>&1 ) || _fail "proj setup"
TIP=$(sc_tip "$SLSTORE" "$SLPROJ")
sc_is40 "$TIP" "proj tip"

# the committed `be` is a `120000` blob (kind l) whose target is ".", NEVER a
# 160000 gitlink — and classify's recursive wtScan in the SOURCE wt did NOT
# blow up into be/be/be (it returned, the post above succeeded).
cat > "$WORK/.mode.js" <<'EOF'
const be    = require(process.argv[3] + "/core/discover.js");
const store = require(process.argv[3] + "/shared/store.js");
const info  = be.find(process.argv[2]);
const k = store.open(info.storePath, info.project);
const tip = k.resolveRef("");
const tree = k.commitTree(tip);
let mode = "", kind = "", sha = "";
k.readTreeRecursive(tree, function (l) {
  if (l.path === "be") { mode = (l.mode || 0).toString(8); kind = l.kind; sha = l.sha; }
});
// the blob bytes of the `be` symlink == its link target "."
let tgt = "";
if (sha) { const o = k.getObject(sha); if (o) tgt = utf8.Decode(o.bytes); }
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+16);b.feed(u);io.write(1,b);}
w(mode + " " + kind + " [" + tgt + "]");
EOF
_info=$("$JABC" "$WORK/.mode.js" "$SLSTORE" "$BEDIR" 2>/dev/null)
[ "$_info" = "120000 l [.]" ] \
    || _fail "committed \`be\` is [$_info] != [120000 l [.]] (must be a 120000 symlink-blob -> .)"

# the recursive wt walk does NOT descend the `be -> .` self-link: io.readdir
# recursive lists `be` ONCE as a leaf (no trailing `/`, no be/be/be/...).
cat > "$WORK/.walk.js" <<'EOF'
const names = io.readdir(process.argv[2], { recursive: true, hidden: true });
let nbe = 0, deep = "";
for (const n of names) {
  if (n === "be") nbe++;
  if (n.indexOf("be/be") === 0) deep = n;     // a descended self-link would yield be/be/...
}
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+16);b.feed(u);io.write(1,b);}
w(nbe + " [" + deep + "]");
EOF
_walk=$("$JABC" "$WORK/.walk.js" "$SLSTORE" 2>/dev/null)
[ "$_walk" = "1 []" ] \
    || _fail "recursive wt walk descended the self-link: [$_walk] (expected '1 []' — \`be\` once, no be/be/...)"

# ============================================================================
# GET: clone the project — `be -> .` materialises via the GENERIC symlink leaf
# (no `be`-name special-case), the checkout COMPLETES, no `?/be` sub fetched.
# ============================================================================
T1="$WORK/get1"
_rc=$(sc_jget "$T1" "be:$SLSTORE/.be?/proj")
[ "$_rc" = 0 ] || { echo "--- get1 err ---"; cat "$WORK/last.err"; _fail "get1 exit $_rc (a 120000 self-link must not abort)"; }

[ -L "$T1/be" ] || _fail "get1: \`be\` is not a symlink (a 120000 blob must check out via io.symlink)"
_tgt=$(readlink "$T1/be")
[ "$_tgt" = "." ] || _fail "get1: \`be\` -> [$_tgt] != [.] (relative self-locator)"
[ -f "$T1/main.c" ] || _fail "get1: main.c missing — checkout aborted (partial wt)"
[ -f "$T1/lib.c" ]  || _fail "get1: lib.c missing — checkout aborted (partial wt)"

# NO stray `be` sub shard was fetched (a symlink is never a submodule mount).
[ -e "$SLSTORE/.be/be" ] && _fail "get1: a stray \`be\` sub shard was fetched (a 120000 symlink must never sub-mount)"

echo "ok   \`be -> .\` (120000 symlink-blob) round-trips, never recursed, never mounted"
pass
