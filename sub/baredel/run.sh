#!/bin/sh
# test/sub/baredel — SUBS-044: bare `jab delete` (no path arg) must sweep a
# sub-interior `mis` (tracked, deleted on disk) INSIDE the mounted submodule
# (its own wtlog), recursing PRE-ORDER.  Before the fix, del_sweep_missing
# `return`ed at the gitlink leaf, dropping the sub `mis`.
#
# JAB-003: native `be` is retired as the stdout oracle (jab emits true hunks,
# native stays columnar); stdout is snapshotted against a committed golden.
# Asserts:
#   1. jab delete sweeps the parent `mis` AND the sub `mis` (sub row in the
#      sub's OWN wtlog, parent wtlog carries only the parent row — no gitlink
#      bump); stdout matches the golden (date column normalised).
#   2. an UNMOUNTED gitlink is still skipped (no descent, no row).
#
# Pure local `be:` keeper wire, reuses the DIS-058 sub harness.
. "$(dirname "$0")/../lib/subcase.sh"
. "$_ROOT/lib/golden.sh"                          # JAB-003: golden_assert
GOLDEN=${GOLDEN:-$_CASE/golden.out}               # JAB-003: committed snapshot

sc_build_parent

# ---- 1. bare delete sweeps a parent mis + a sub-interior mis ----
# JAB-003: single JS side; native `be` oracle dropped, stdout -> golden.
run_side() { # $1=dest — jab clone, delete parent+sub mis
  sc_jget "$1" "be:$PARSTORE/.be?/par" >/dev/null
  [ -f "$1/vendor/sub/helper.c" ] || _fail "$1: sub not mounted/checked out"
  rm -f "$1/main.c"                 # parent mis
  rm -f "$1/vendor/sub/helper.c"    # sub mis
  ( cd "$1" && "$JABC" delete ) > "$1.out" 2>"$1.err" || true
}
JS="$WORK/js"
run_side "$JS"

#  JAB-003: snapshot jab's stdout against the committed golden.
golden_assert "$NAME" "$GOLDEN" < "$JS.out"

#  The sub `mis` is swept into the SUB's OWN wtlog (the secondary-wt `.be` anchor).
grep -qE 'delete[[:space:]]+helper\.c' "$JS/vendor/sub/.be" \
    || _fail "jab: sub mis helper.c not swept in sub wtlog: $(cat "$JS/vendor/sub/.be")"
#  The parent `mis` is swept into the PARENT wtlog; no gitlink bump.
grep -qE 'delete[[:space:]]+main\.c' "$JS/.be/wtlog" \
    || _fail "jab: parent mis main.c not swept"
grep -qE 'put[[:space:]]+vendor/sub#' "$JS/.be/wtlog" \
    && _fail "jab: parent gitlink bumped by delete (should be POST's job)"
echo "ok   1. bare delete sweeps parent + sub mis (sub wtlog), no gitlink bump, golden"

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
