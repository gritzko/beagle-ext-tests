#!/bin/sh
# test/sub/bareput — SUBS-044: bare `jab put` (no path arg) must stage a
# sub-interior `mod` file INSIDE the mounted submodule (its own wtlog), matching
# native `be put`, which recurses PRE-ORDER ([Submodules]).  Before the fix,
# bareStage `return`ed at the gitlink leaf and left the sub `mod` unstaged.
#
# Asserts, against the NATIVE oracle on an identical clone:
#   1. jab put stages the parent `mod` AND the sub `mod` (sub row in the sub's
#      OWN wtlog, parent wtlog carries only the parent row — no gitlink bump,
#      that's POST's job), with byte-identical stdout (date column normalised).
#   2. an UNMOUNTED gitlink is still skipped (no descent, no row).
#
# Pure local `be:` keeper wire, reuses the DIS-058 sub harness.
. "$(dirname "$0")/../lib/subcase.sh"

_norm() { sed -E 's/^ *[0-9]{1,2}:[0-9]{2} +/T /' "$1"; }

sc_build_parent

# ---- 1. bare put stages a parent mod + a sub-interior mod ----
#  Clone the SAME parent into a native side and a jab side; mutate identically.
run_side() { # $1=client $2=dest
  sc_jget "$2" "be:$PARSTORE/.be?/par" >/dev/null
  [ -f "$2/vendor/sub/lib.c" ] || _fail "$2: sub not mounted/checked out"
  printf 'int main(void){return 7;}\n' > "$2/main.c"          # parent mod
  printf 'sub payload v1 EDITED\n'     > "$2/vendor/sub/lib.c" # sub mod
  ( cd "$2" && "$1" put ) > "$2.out" 2>"$2.err" || true
}
NAT="$WORK/nat"; JS="$WORK/js"
run_side "$BE"   "$NAT"
run_side "$JABC" "$JS"

#  stdout byte-parity (date column normalised — the only normalisation).
_norm "$NAT.out" > "$WORK/nat.norm"; _norm "$JS.out" > "$WORK/js.norm"
cmp -s "$WORK/nat.norm" "$WORK/js.norm" || {
    echo "--- native stdout ---"; cat "$NAT.out"
    echo "--- jab stdout ---";    cat "$JS.out"
    echo "--- diff (normalised) ---"; diff "$WORK/nat.norm" "$WORK/js.norm" || true
    _fail "bare put stdout differs"; }

#  The sub `mod` is staged in the SUB's OWN wtlog (the secondary-wt `.be` anchor).
grep -qE 'put[[:space:]]+lib\.c' "$JS/vendor/sub/.be" \
    || _fail "jab: sub mod lib.c not staged in sub wtlog: $(cat "$JS/vendor/sub/.be")"
#  The parent `mod` is staged in the PARENT wtlog; the gitlink is NOT bumped here.
grep -qE 'put[[:space:]]+main\.c' "$JS/.be/wtlog" \
    || _fail "jab: parent mod main.c not staged"
grep -qE 'put[[:space:]]+vendor/sub#' "$JS/.be/wtlog" \
    && _fail "jab: parent gitlink bumped by put (should be POST's job)"
echo "ok   1. bare put stages parent + sub mod (sub wtlog), no gitlink bump, parity"

# ---- 2. an UNMOUNTED gitlink is skipped (no descent, no spurious row) ----
#  Unmount the sub (remove its `.be` anchor → recurse.isMount NO); the sub's
#  on-disk lib.c stays dirty but bare put must NOT descend (it's a gitlink, not
#  a mount).  The parent main.c still stages.
T2="$WORK/unm"; sc_jget "$T2" "be:$PARSTORE/.be?/par" >/dev/null
rm -f "$T2/vendor/sub/.be"                                   # unmount
printf 'int main(void){return 9;}\n' > "$T2/main.c"
printf 'sub payload v1 EDITED\n'     > "$T2/vendor/sub/lib.c"
( cd "$T2" && "$JABC" put ) > "$T2.out" 2>"$T2.err" || _fail "unmounted put exit"
grep -qE 'put[[:space:]]+main\.c' "$T2/.be/wtlog" \
    || _fail "unmounted: parent main.c not staged"
grep -qE 'vendor/sub' "$T2.out" \
    && _fail "unmounted: bare put descended into an UNMOUNTED gitlink"
echo "ok   2. UNMOUNTED gitlink skipped by bare put"

pass
