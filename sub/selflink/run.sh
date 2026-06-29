#!/bin/sh
# test/sub/selflink — GET-037: `jab get` of a project carrying the `be` SELF-
# LOCATOR gitlink.  A project pins its OWN commit as a `160000` gitlink named
# `be` (so `jab`'s upward `be`-scan resolves the extension as the `be` shard,
# see [GET-036]) — with NO `.gitmodules` entry (only real subs are declared).
#
# Before GET-037 the DIS-058 mount-recursion treated EVERY gitlink as a sub:
# for `be`, `gitmodulesUrl`→"" → title `basename("be")="be"` → fetch `?/be`
# (no such child) → ABORT mid-checkout (a partial wt: `.be`,`.gitmodules`,…) and
# a friendly SUBFETCH (canonical store) / a RAW ENOTDIR (worktree source).
#
# GET-037: the self-locator must materialise `be -> .` ([GET-036]) and SKIP the
# sub-mount + recursion — the checkout then COMPLETES.  A real sub (WITH a
# `.gitmodules` url) must still mount (sub/cycle covers that; do not regress).
#
# Pure local `be:` keeper wire (no git, no network) — CI-friendly.
. "$(dirname "$0")/../lib/subcase.sh"

# --- build a parent store that commits a `be` self-locator gitlink -----------
# A primary `be:` store with one baseline commit, then a SECOND commit that adds
# a `160000` gitlink named `be` pinned at the FIRST commit (the project's own
# commit) with NO `.gitmodules` entry — exactly the beagle-ext self-locator.
SLSTORE="$WORK/proj"
SLPROJ="proj"
rm -rf "$SLSTORE"
mkdir -p "$SLSTORE/.be"

( cd "$SLSTORE"
  printf 'hello from proj\n' > main.c
  printf 'extra payload\n'   > lib.c
  "$BE" post '#proj initial' >/dev/null 2>&1 ) || _fail "proj setup"
OWNTIP=$(sc_tip "$SLSTORE" "$SLPROJ")
sc_is40 "$OWNTIP" "proj own tip"

# Stage the `be` self-locator gitlink (a `put be#<own-commit>` row in the
# staging wtlog — the same shape sub/cycle asserts for a real sub gitlink, but
# WITHOUT a `.gitmodules` entry) via ulog.append (mints a fresh, monotonic stamp
# — a raw printf would reuse a stale ts and trip ULOGCLOCK), then post it.
cat > "$WORK/.stage.js" <<'EOF'
const ulog = require(process.argv[3] + "/shared/ulog.js");
ulog.append(process.argv[2], [{ verb: "put", uri: "be#" + process.argv[4] }]);
EOF
"$JABC" "$WORK/.stage.js" "$SLSTORE/.be/wtlog" "$BEDIR" "$OWNTIP" >/dev/null 2>&1 \
    || _fail "stage self-locator (ulog.append)"
( cd "$SLSTORE" && "$BE" post '#self-locator be' >/dev/null 2>&1 ) \
    || _fail "post self-locator"
SLTIP=$(sc_tip "$SLSTORE" "$SLPROJ")
sc_is40 "$SLTIP" "proj tip with self-locator"

# the `be` gitlink IS in the baseline tree (a 160000 entry, no .gitmodules).
grep -qE 'put[[:space:]]+be#[0-9a-f]{40}' "$SLSTORE/.be/wtlog" \
    || _fail "self-locator gitlink not committed: $(cat "$SLSTORE/.be/wtlog")"
[ -f "$SLSTORE/.gitmodules" ] && _fail "fixture wrongly has a .gitmodules"

# ============================================================================
# GET: clone the project — the self-locator must materialise `be -> .` and the
# checkout must COMPLETE (all files present, exit 0, no partial wt).
# ============================================================================
T1="$WORK/get1"
_rc=$(sc_jget "$T1" "be:$SLSTORE/.be?/proj")
[ "$_rc" = 0 ] || { echo "--- get1 err ---"; cat "$WORK/last.err"; _fail "get1 exit $_rc (self-locator must not abort)"; }

# `be` is the relative self-symlink `be -> .` ([GET-036]) — NOT a dir, NOT a
# sub-mount, NOT a fetched `?/be` child.
[ -L "$T1/be" ] || _fail "get1: \`be\` is not a symlink (self-locator must be \`be -> .\`)"
_tgt=$(readlink "$T1/be")
[ "$_tgt" = "." ] || _fail "get1: \`be\` -> [$_tgt] != [.] (relative self-locator, GET-036)"

# the rest of the checkout COMPLETED (no partial wt: the project's own files).
[ -f "$T1/main.c" ] || _fail "get1: main.c missing — checkout aborted (partial wt)"
[ -f "$T1/lib.c" ]  || _fail "get1: lib.c missing — checkout aborted (partial wt)"
_got=$(cat "$T1/main.c")
[ "$_got" = "hello from proj" ] || _fail "get1: main.c [$_got] != [hello from proj]"

# NO stray sub shard was fetched for `be` (no `?/be` child) — the store dir
# (next to the source shard) holds NO `be` shard.
[ -e "$SLSTORE/.be/be" ] && _fail "get1: a stray \`be\` sub shard was fetched (must skip sub-mount)"

echo "ok   GET: \`be\` self-locator materialised as \`be -> .\`, checkout completed"
pass
