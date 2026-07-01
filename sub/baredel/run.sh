#!/bin/sh
# test/sub/baredel — SUBS-044: bare `jab delete` (no path arg) must sweep a
# sub-interior `mis` (tracked, deleted on disk) INSIDE the mounted submodule
# (its own wtlog), matching native `be delete`, which recurses PRE-ORDER.
# Before the fix, del_sweep_missing `return`ed at the gitlink leaf, dropping the
# sub `mis`.
#
# Asserts, against the NATIVE oracle on an identical clone:
#   1. jab delete sweeps the parent `mis` AND the sub `mis` (sub row in the
#      sub's OWN wtlog, parent wtlog carries only the parent row — no gitlink
#      bump), with byte-identical stdout (date column normalised).
#   2. an UNMOUNTED gitlink is still skipped (no descent, no row).
#
# Pure local `be:` keeper wire, reuses the DIS-058 sub harness.
. "$(dirname "$0")/../lib/subcase.sh"

_norm() { sed -E 's/^ *[0-9]{1,2}:[0-9]{2} +/T /' "$1"; }

sc_build_parent

# ---- 1. bare delete sweeps a parent mis + a sub-interior mis ----
run_side() { # $1=client $2=dest
  sc_jget "$2" "be:$PARSTORE/.be?/par" >/dev/null
  [ -f "$2/vendor/sub/helper.c" ] || _fail "$2: sub not mounted/checked out"
  rm -f "$2/main.c"                 # parent mis
  rm -f "$2/vendor/sub/helper.c"    # sub mis
  ( cd "$2" && "$1" delete ) > "$2.out" 2>"$2.err" || true
}
NAT="$WORK/nat"; JS="$WORK/js"
run_side "$BE"   "$NAT"
run_side "$JABC" "$JS"

#  stdout byte-parity (date column normalised).
_norm "$NAT.out" > "$WORK/nat.norm"; _norm "$JS.out" > "$WORK/js.norm"
cmp -s "$WORK/nat.norm" "$WORK/js.norm" || {
    echo "--- native stdout ---"; cat "$NAT.out"
    echo "--- jab stdout ---";    cat "$JS.out"
    echo "--- diff (normalised) ---"; diff "$WORK/nat.norm" "$WORK/js.norm" || true
    _fail "bare delete stdout differs"; }

#  The sub `mis` is swept into the SUB's OWN wtlog (the secondary-wt `.be` anchor).
grep -qE 'delete[[:space:]]+helper\.c' "$JS/vendor/sub/.be" \
    || _fail "jab: sub mis helper.c not swept in sub wtlog: $(cat "$JS/vendor/sub/.be")"
#  The parent `mis` is swept into the PARENT wtlog; no gitlink bump.
grep -qE 'delete[[:space:]]+main\.c' "$JS/.be/wtlog" \
    || _fail "jab: parent mis main.c not swept"
grep -qE 'put[[:space:]]+vendor/sub#' "$JS/.be/wtlog" \
    && _fail "jab: parent gitlink bumped by delete (should be POST's job)"
echo "ok   1. bare delete sweeps parent + sub mis (sub wtlog), no gitlink bump, parity"

# ---- 2. an UNMOUNTED gitlink is skipped ----
T2="$WORK/unm"; sc_jget "$T2" "be:$PARSTORE/.be?/par" >/dev/null
rm -f "$T2/vendor/sub/.be"                                   # unmount
rm -f "$T2/main.c"
rm -f "$T2/vendor/sub/helper.c"
( cd "$T2" && "$JABC" delete ) > "$T2.out" 2>"$T2.err" || _fail "unmounted delete exit"
grep -qE 'delete[[:space:]]+main\.c' "$T2/.be/wtlog" \
    || _fail "unmounted: parent main.c not swept"
grep -qE 'vendor/sub' "$T2.out" \
    && _fail "unmounted: bare delete descended into an UNMOUNTED gitlink"
echo "ok   2. UNMOUNTED gitlink skipped by bare delete"

pass
