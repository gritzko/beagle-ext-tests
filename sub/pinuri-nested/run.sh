#!/bin/sh
# test/sub/pinuri-nested — DIS-072: a sub-of-a-sub tracks its pin FLAT under the
# owning tree top (`//WT/vendor/sub/vendor/inner#<pin>`), never the dotted
# `.parent/.grandparent` synthetic chain (RULED 2026-07-15: nesting is FLAT).
# Builds par -> vendor/sub -> vendor/inner (all gitlinks committed at the
# stores), then a fresh clone mounts BOTH levels; the grandchild's track row
# is asserted.
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent     # par -> vendor/sub

# a grandchild `inner` store (one tracked file, one commit).
INNERSTORE="$WORK/inner"
rm -rf "$INNERSTORE"; mkdir -p "$INNERSTORE/.be"
( cd "$INNERSTORE"
  printf 'inner payload v1\n' > deep.c
  "$BE" post '#inner initial' >/dev/null 2>&1 ) || _fail "inner setup"
INNERTIP0=$(sc_tip "$INNERSTORE")
sc_is40 "$INNERTIP0" "inner tip0"

# commit the inner gitlink INTO the sub store (decl + anchor + checkout + pin).
( cd "$SUBSTORE"
  cat > .gitmodules <<EOF
[submodule "vendor/inner"]
	path = vendor/inner
	url = file://$INNERSTORE/.be?/inner
EOF
  mkdir -p vendor/inner
  _r=$(awk -F'\t' 'NR==1{print $1; exit}' .be/wtlog)
  printf '%s\tget\tfile:%s/.be/?/#%s\n' "$_r" "$INNERSTORE" "$INNERTIP0" \
      > vendor/inner/.be
  printf 'inner payload v1\n' > vendor/inner/deep.c
  "$BE" put .gitmodules >/dev/null 2>&1 ) || _fail "mount inner (put)"
sc_pin_gitlink "vendor/inner" "$SUBSTORE/.be/wtlog" "$INNERTIP0"
( cd "$SUBSTORE" && "$BE" post '#mount inner' >/dev/null 2>&1 ) || _fail "mount inner (post)"
SUBTIP1=$(sc_tip "$SUBSTORE")
sc_is40 "$SUBTIP1" "sub tip1"

# bump the parent's vendor/sub gitlink to the inner-carrying sub commit.
sc_pin_gitlink "$SUBPATH" "$PARSTORE/.be/wtlog" "$SUBTIP1"
( cd "$PARSTORE" && "$BE" post '#bump sub' >/dev/null 2>&1 ) || _fail "bump sub gitlink"

# --- a fresh clone mounts BOTH levels ---------------------------------------
T2="$WORK/t2"
rc=$(sc_jget "$T2" "file://$PARSTORE/.be")
[ "$rc" = 0 ] || { cat "$WORK/last.err" >&2; _fail "clone parent rc=$rc"; }
[ -f "$T2/vendor/sub/lib.c" ] || _fail "sub not mounted"
[ -f "$T2/vendor/sub/vendor/inner/deep.c" ] || _fail "grandchild not mounted"

# the grandchild tracks the FLAT pin URI under the owning tree top.
ANCH=$(od -An -c "$T2/vendor/sub/vendor/inner/.be" | tr -d ' \n')
case "$ANCH" in
  *"///vendor/sub/vendor/inner#$INNERTIP0"*) ;;
  *) _fail "grandchild does not track ///vendor/sub/vendor/inner#$INNERTIP0: $(cat "$T2/vendor/sub/vendor/inner/.be")" ;;
esac
case "$ANCH" in
  *"?/inner/."*|*"/.par"*) _fail "grandchild recorded a dotted synthetic chain: $(cat "$T2/vendor/sub/vendor/inner/.be")" ;;
esac

# the middle sub tracks its own flat pin URI too.
ANCH=$(od -An -c "$T2/vendor/sub/.be" | tr -d ' \n')
case "$ANCH" in
  *"///vendor/sub#$SUBTIP1"*) ;;
  *) _fail "sub does not track ///vendor/sub#$SUBTIP1: $(cat "$T2/vendor/sub/.be")" ;;
esac

pass
