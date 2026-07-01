#!/bin/sh
# test/sub/baredel-nested — SUBS-044: bare `jab delete` must recurse NESTED
# mounted subs (sub-of-sub), sweeping a `mis` at the deepest level, matching
# native `be delete` PRE-ORDER recursion.  Builds par -> vendor/sub via the
# DIS-058 harness, clones it, mounts a GRANDCHILD `inner` inside the cloned
# `vendor/sub`, deletes a grandchild file, and asserts native==jab stdout +
# the grandchild `mis` row landing in the grandchild's OWN wtlog.
. "$(dirname "$0")/../lib/subcase.sh"

_norm() { sed -E 's/^ *[0-9]{1,2}:[0-9]{2} +/T /' "$1"; }

sc_build_parent

INNERSTORE="$WORK/inner"
rm -rf "$INNERSTORE"; mkdir -p "$INNERSTORE/.be"
( cd "$INNERSTORE"
  printf 'inner payload v1\n' > deep.c
  printf 'inner helper\n'     > deeph.c
  "$BE" post '#inner initial' >/dev/null 2>&1 ) || _fail "inner setup"
INNERTIP0=$(sc_tip "$INNERSTORE" "inner")
sc_is40 "$INNERTIP0" "inner tip0"

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
  printf 'inner helper\n'     > "$SUBWT/vendor/inner/deeph.c"
  ( cd "$SUBWT" && "$BE" put .gitmodules >/dev/null 2>&1 \
    && "$BE" put vendor/inner >/dev/null 2>&1 \
    && "$BE" post '#mount inner' >/dev/null 2>&1 ) || _fail "mount inner in $1"
}
run_side() { # $1=client $2=dest
  sc_jget "$2" "be:$PARSTORE/.be?/par" >/dev/null
  [ -f "$2/vendor/sub/lib.c" ] || _fail "$2: sub not mounted"
  mount_inner "$2"
  [ -f "$2/vendor/sub/vendor/inner/deeph.c" ] || _fail "$2: grandchild not mounted"
  rm -f "$2/vendor/sub/vendor/inner/deeph.c"     # grandchild mis
  ( cd "$2" && "$1" delete ) > "$2.out" 2>"$2.err" || true
}
NAT="$WORK/nat"; JS="$WORK/js"
run_side "$BE"   "$NAT"
run_side "$JABC" "$JS"

_norm "$NAT.out" > "$WORK/nat.norm"; _norm "$JS.out" > "$WORK/js.norm"
cmp -s "$WORK/nat.norm" "$WORK/js.norm" || {
    echo "--- native stdout ---"; cat "$NAT.out"
    echo "--- jab stdout ---";    cat "$JS.out"
    echo "--- diff (normalised) ---"; diff "$WORK/nat.norm" "$WORK/js.norm" || true
    _fail "nested bare delete stdout differs"; }

grep -qE 'delete[[:space:]]+deeph\.c' "$JS/vendor/sub/vendor/inner/.be" \
    || _fail "jab: grandchild mis deeph.c not swept in grandchild wtlog"
echo "ok   nested bare delete recurses sub-of-sub (grandchild wtlog), parity"

pass
