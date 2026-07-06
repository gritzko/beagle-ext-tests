#!/bin/sh
# test/sub/bareput-nested — SUBS-044: bare `jab put` must recurse NESTED mounted
# subs (sub-of-sub), staging a `mod` at the deepest level, matching native `be
# put` PRE-ORDER recursion.  Builds par -> vendor/sub via the DIS-058 harness,
# clones it, then mounts a GRANDCHILD `inner` store directly inside the cloned
# `vendor/sub` (a `.gitmodules` decl + secondary-wt `.be` anchor + checkout — a
# live mount, which is all recurse.walk's gate needs).  A `mod` in the grandchild
# JAB-003: must be staged into the grandchild's OWN wtlog; golden-snapshotted.
# TEST-003 FLAGGED: needs the JS-keeper feature — the mounted sub CHILD is
# fetched over the git/keeper WIRE (submount.mount), no keeper-free local path.
. "$(dirname "$0")/../lib/subcase.sh"
. "$_ROOT/lib/golden.sh"                          # JAB-003: golden_assert
GOLDEN=${GOLDEN:-$_CASE/golden.out}               # JAB-003: committed snapshot

sc_build_parent     # par -> vendor/sub

# A grandchild `inner` store (one tracked file, one commit).
INNERSTORE="$WORK/inner"
rm -rf "$INNERSTORE"; mkdir -p "$INNERSTORE/.be"
( cd "$INNERSTORE"
  printf 'inner payload v1\n' > deep.c
  "$BE" post '#inner initial' >/dev/null 2>&1 ) || _fail "inner setup"
INNERTIP0=$(sc_tip "$INNERSTORE" "inner")
sc_is40 "$INNERTIP0" "inner tip0"

# JAB-003: clone the parent into the jab side, mount `inner` inside the cloned
# vendor/sub (.gitmodules decl + anchor + checkout), dirty the grandchild, put.
mount_inner() { # $1 = cloned-parent dir
  SUBWT="$1/vendor/sub"
  cat > "$SUBWT/.gitmodules" <<EOF
[submodule "vendor/inner"]
	path = vendor/inner
	url = file://$INNERSTORE/.be?/inner
EOF
  mkdir -p "$SUBWT/vendor/inner"
  _r=$(awk -F'\t' 'NR==1{print $1; exit}' "$SUBWT/.be")
  printf '%s\tget\tfile:%s/.be/?/#%s\n' "$_r" "$INNERSTORE" "$INNERTIP0" \
      > "$SUBWT/vendor/inner/.be"
  printf 'inner payload v1\n' > "$SUBWT/vendor/inner/deep.c"
  #  Commit the inner gitlink into the SUB so its baseline tree carries it (so
  #  the sub's bareStage sees `inner` as a tracked gitlink, and recurse.walk's
  #  `.gitmodules` gate + the `<inner>/.be` mount let the descent reach it).
  #  TEST-003: jab has no CLI spelling to stage a raw NEW gitlink (`jab put
  #  vendor/inner` → PUTNONE) — seed the pin into the SUB's store-backed `.be`
  #  wtlog via sc_pin_gitlink, then post folds it into the baseline tree.
  ( cd "$SUBWT" && "$BE" put .gitmodules >/dev/null 2>&1 ) || _fail "mount inner (gitmodules) in $1"
  sc_pin_gitlink "vendor/inner" "$SUBWT/.be" "$INNERTIP0"
  ( cd "$SUBWT" && "$BE" post '#mount inner' >/dev/null 2>&1 ) || _fail "mount inner (post) in $1"
}
run_side() { # $1=client $2=dest
  sc_jget "$2" "file://$PARSTORE/.be" >/dev/null
  [ -f "$2/vendor/sub/lib.c" ] || _fail "$2: sub not mounted"
  mount_inner "$2"
  [ -f "$2/vendor/sub/vendor/inner/deep.c" ] || _fail "$2: grandchild not mounted"
  printf 'inner payload v1 EDITED\n' > "$2/vendor/sub/vendor/inner/deep.c"
  ( cd "$2" && "$1" put ) > "$2.out" 2>"$2.err" || true
}
JS="$WORK/js"                                     # JAB-003: JS side only; native oracle retired
run_side "$JABC" "$JS"

# JAB-003: golden-snapshot the jab bare-put stdout (was native-vs-jab cmp).
cat "$JS.out" | golden_assert "$NAME" "$GOLDEN"

#  The grandchild `mod` lands in the GRANDCHILD's own wtlog.
grep -qE 'put[[:space:]]+deep\.c' "$JS/vendor/sub/vendor/inner/.be" \
    || _fail "jab: grandchild mod deep.c not staged in grandchild wtlog: $(cat "$JS/vendor/sub/vendor/inner/.be")"
echo "ok   nested bare put recurses sub-of-sub (grandchild wtlog)"

pass
