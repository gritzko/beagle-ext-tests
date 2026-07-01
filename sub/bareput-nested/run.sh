#!/bin/sh
# test/sub/bareput-nested — SUBS-044: bare `jab put` must recurse NESTED mounted
# subs (sub-of-sub), staging a `mod` at the deepest level, matching native `be
# put` PRE-ORDER recursion.  Builds par -> vendor/sub via the DIS-058 harness,
# clones it, then mounts a GRANDCHILD `inner` store directly inside the cloned
# `vendor/sub` (a `.gitmodules` decl + secondary-wt `.be` anchor + checkout — a
# live mount, which is all recurse.walk's gate needs).  A `mod` in the grandchild
# must be staged into the grandchild's OWN wtlog, byte-parity vs native.
. "$(dirname "$0")/../lib/subcase.sh"

_norm() { sed -E 's/^ *[0-9]{1,2}:[0-9]{2} +/T /' "$1"; }

sc_build_parent     # par -> vendor/sub

# A grandchild `inner` store (one tracked file, one commit).
INNERSTORE="$WORK/inner"
rm -rf "$INNERSTORE"; mkdir -p "$INNERSTORE/.be"
( cd "$INNERSTORE"
  printf 'inner payload v1\n' > deep.c
  "$BE" post '#inner initial' >/dev/null 2>&1 ) || _fail "inner setup"
INNERTIP0=$(sc_tip "$INNERSTORE" "inner")
sc_is40 "$INNERTIP0" "inner tip0"

# Clone the parent into a native + jab side; in EACH, mount `inner` inside the
# cloned vendor/sub (declare it in the sub's .gitmodules + write the anchor +
# checkout), then dirty the grandchild and bare put.  Both sides are identical.
mount_inner() { # $1 = cloned-parent dir
  SUBWT="$1/vendor/sub"
  cat > "$SUBWT/.gitmodules" <<EOF
[submodule "vendor/inner"]
	path = vendor/inner
	url = be:$INNERSTORE/.be?/inner
EOF
  mkdir -p "$SUBWT/vendor/inner"
  _r=$(awk -F'\t' 'NR==1{print $1; exit}' "$SUBWT/.be")
  printf '%s\tget\tfile:%s/.be/?/inner#%s\n' "$_r" "$INNERSTORE" "$INNERTIP0" \
      > "$SUBWT/vendor/inner/.be"
  printf 'inner payload v1\n' > "$SUBWT/vendor/inner/deep.c"
  #  Commit the inner gitlink into the SUB so its baseline tree carries it (so
  #  the sub's bareStage sees `inner` as a tracked gitlink, and recurse.walk's
  #  `.gitmodules` gate + the `<inner>/.be` mount let the descent reach it).
  ( cd "$SUBWT" && "$BE" put .gitmodules >/dev/null 2>&1 \
    && "$BE" put vendor/inner >/dev/null 2>&1 \
    && "$BE" post '#mount inner' >/dev/null 2>&1 ) || _fail "mount inner in $1"
}
run_side() { # $1=client $2=dest
  sc_jget "$2" "be:$PARSTORE/.be?/par" >/dev/null
  [ -f "$2/vendor/sub/lib.c" ] || _fail "$2: sub not mounted"
  mount_inner "$2"
  [ -f "$2/vendor/sub/vendor/inner/deep.c" ] || _fail "$2: grandchild not mounted"
  printf 'inner payload v1 EDITED\n' > "$2/vendor/sub/vendor/inner/deep.c"
  ( cd "$2" && "$1" put ) > "$2.out" 2>"$2.err" || true
}
NAT="$WORK/nat"; JS="$WORK/js"
run_side "$BE"   "$NAT"
run_side "$JABC" "$JS"

_norm "$NAT.out" > "$WORK/nat.norm"; _norm "$JS.out" > "$WORK/js.norm"
cmp -s "$WORK/nat.norm" "$WORK/js.norm" || {
    echo "--- native stdout ---"; cat "$NAT.out"
    echo "--- jab stdout ---";    cat "$JS.out"
    echo "--- diff (normalised) ---"; diff "$WORK/nat.norm" "$WORK/js.norm" || true
    _fail "nested bare put stdout differs"; }

#  The grandchild `mod` lands in the GRANDCHILD's own wtlog.
grep -qE 'put[[:space:]]+deep\.c' "$JS/vendor/sub/vendor/inner/.be" \
    || _fail "jab: grandchild mod deep.c not staged in grandchild wtlog: $(cat "$JS/vendor/sub/vendor/inner/.be")"
echo "ok   nested bare put recurses sub-of-sub (grandchild wtlog), parity"

pass
