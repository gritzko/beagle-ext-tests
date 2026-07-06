#!/bin/sh
# test/sub/bareput — SUBS-044: bare `jab put` (no path arg) must stage a
# sub-interior `mod` file INSIDE the mounted submodule (its own wtlog).  Before
# the fix, bareStage `return`ed at the gitlink leaf and left the sub `mod`
# unstaged.
#
# JAB-003: native `be put` is retired as the stdout oracle (it stays columnar
# while jab emits true hunks); step 1's stdout is now a committed golden.
# Asserts:
#   1. jab put stages the parent `mod` AND the sub `mod` (sub row in the sub's
#      OWN wtlog, parent wtlog carries only the parent row — no gitlink bump,
#      that's POST's job), with stdout matching the golden (date column folded).
#   2. an UNMOUNTED gitlink is still skipped (no descent, no row).
#
# TEST-003 FLAGGED: needs the JS-keeper feature — the mounted sub CHILD is
# fetched over the git/keeper WIRE (submount.mount), no keeper-free local path.
. "$(dirname "$0")/../lib/subcase.sh"
# JAB-003: golden-snapshot assertion + committed per-case golden.
. "$_ROOT/lib/golden.sh"
GOLDEN=${GOLDEN:-$_CASE/golden.out}

sc_build_parent

# ---- 1. bare put stages a parent mod + a sub-interior mod ----
# JAB-003: clone the parent into the jab side only; the native oracle is retired.
run_side() { # $1=client $2=dest
  sc_jget "$2" "file://$PARSTORE/.be" >/dev/null
  [ -f "$2/vendor/sub/lib.c" ] || _fail "$2: sub not mounted/checked out"
  printf 'int main(void){return 7;}\n' > "$2/main.c"          # parent mod
  printf 'sub payload v1 EDITED\n'     > "$2/vendor/sub/lib.c" # sub mod
  ( cd "$2" && "$1" put ) > "$2.out" 2>"$2.err" || true
}
JS="$WORK/js"
run_side "$JABC" "$JS"

# JAB-003: snapshot jab put stdout against the committed golden (date folded).
golden_assert "$NAME" "$GOLDEN" < "$JS.out"

#  The sub `mod` is staged in the SUB's OWN wtlog (the secondary-wt `.be` anchor).
grep -qE 'put[[:space:]]+lib\.c' "$JS/vendor/sub/.be" \
    || _fail "jab: sub mod lib.c not staged in sub wtlog: $(cat "$JS/vendor/sub/.be")"
#  The parent `mod` is staged in the PARENT wtlog; the gitlink is NOT bumped here.
#  TEST-003: store-backed clone — the parent wtlog IS the `.be` FILE (rows inline).
grep -qE 'put[[:space:]]+main\.c' "$JS/.be" \
    || _fail "jab: parent mod main.c not staged"
grep -qE 'put[[:space:]]+vendor/sub#' "$JS/.be" \
    && _fail "jab: parent gitlink bumped by put (should be POST's job)"
echo "ok   1. bare put stages parent + sub mod (sub wtlog), no gitlink bump, parity"

# ---- 2. an UNMOUNTED gitlink is skipped (no descent, no spurious row) ----
#  Unmount the sub (remove its `.be` anchor → recurse.isMount NO); the sub's
#  on-disk lib.c stays dirty but bare put must NOT descend (it's a gitlink, not
#  a mount).  The parent main.c still stages.
T2="$WORK/unm"; sc_jget "$T2" "file://$PARSTORE/.be" >/dev/null
rm -f "$T2/vendor/sub/.be"                                   # unmount
printf 'int main(void){return 9;}\n' > "$T2/main.c"
printf 'sub payload v1 EDITED\n'     > "$T2/vendor/sub/lib.c"
( cd "$T2" && "$JABC" put ) > "$T2.out" 2>"$T2.err" || _fail "unmounted put exit"
grep -qE 'put[[:space:]]+main\.c' "$T2/.be" \
    || _fail "unmounted: parent main.c not staged"
grep -qE 'vendor/sub' "$T2.out" \
    && _fail "unmounted: bare put descended into an UNMOUNTED gitlink"
echo "ok   2. UNMOUNTED gitlink skipped by bare put"

pass
