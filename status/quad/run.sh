#!/bin/sh
# test/status/quad — BRO-030: FLAGLESS `status` renders the unified quad rows
# (wiki/Status.mkd) as the DEFAULT (the quad canon `.xov`, staged UPPERCASE):
# commit ahead/behind and file dirt share ONE vocabulary — a base-ahead post
# reads `.o..`, a wt-only edit `...v`, an untracked `...o`, a staged-new `...O`;
# the summary swaps bucket counts for quad-COLUMN counts.  RED until the default
# flip lands (the reporter still emits legacy buckets without --quad).
. "$(dirname "$0")/../../sub/lib/subcase.sh"

sc_build_parent

T1="$WORK/get1"
_rc=$(sc_jget "$T1" "file://$PARSTORE/.be")
[ "$_rc" = 0 ] || { echo "--- get1 err ---"; cat "$WORK/last.err"; _fail "clone exit $_rc"; }
SUBWT="$T1/vendor/sub"
[ -f "$SUBWT/lib.c" ] || _fail "get1: sub not mounted/checked out"

# ---- fixture: a base-ahead commit + a dirty + a staged + an untracked file ---
# the ahead post advances the sub's base past its tracked parent pin (root =
# the pin, so the new commit is base-side `.o..` and lib.c reads `.v..`
# (BRO-030 ruling: the wt column is LOCAL dirt vs base, clean = '.').
( cd "$SUBWT" && printf 'sub payload v2\n' > lib.c \
    && "$JABC" put lib.c && "$JABC" post '#quad ahead' ) >/dev/null 2>&1 \
    || _fail "sub: ahead post failed"
# a wt-only edit on a file the post did NOT touch → `...v` (the old `mod`)
printf 'sub helper DIRTY\n' > "$SUBWT/helper.c" || _fail "dirty helper.c"
# a staged NEW file → `...O` (UPPERCASE = staged, plain) + an untracked `...o`
( cd "$SUBWT" && printf 'staged\n' > staged.c && "$JABC" put staged.c ) \
    >/dev/null 2>&1 || _fail "stage staged.c"
printf 'loose\n' > "$SUBWT/untracked.c" || _fail "untracked.c"

# ---- FLAGLESS status is the quad default (wiki/Status.mkd) -------------------
# BRO-030: RED until the default flip lands; append --quad to confirm green.
( cd "$SUBWT" && "$JABC" status --plain ) >"$WORK/q.out" 2>"$WORK/q.err" \
    || { cat "$WORK/q.err"; _fail "status failed"; }
# the base-ahead commit row: `<date7> .o.. ?<hashlet>#quad ahead`
grep -qE '\.o\.\. \?[0-9a-f]{6,40}#quad ahead' "$WORK/q.out" || {
    echo "--- quad status ---"; cat "$WORK/q.out"
    _fail "no .o.. commit row for the base-ahead post"
}
# the wt-only edit: `...v helper.c`
grep -q '\.\.\.v helper\.c$' "$WORK/q.out" || {
    echo "--- quad status ---"; cat "$WORK/q.out"
    _fail "no ...v quad row for the dirty helper.c"
}
# lib.c posted ahead of root: base advanced, wt CLEAN vs base → `.v..`
grep -q '\.v\.\. lib\.c$' "$WORK/q.out" || {
    echo "--- quad status ---"; cat "$WORK/q.out"
    _fail "no .v.. quad row for the base-ahead lib.c"
}
# untracked reads lowercase `...o`; the staged-new reads UPPERCASE `...O`
grep -q '\.\.\.o untracked\.c$' "$WORK/q.out" || {
    echo "--- quad status ---"; cat "$WORK/q.out"
    _fail "no ...o quad row for untracked.c"
}
grep -q '\.\.\.O staged\.c$' "$WORK/q.out" || {
    echo "--- quad status ---"; cat "$WORK/q.out"
    _fail "no ...O (staged) quad row for the staged new file"
}
# the summary carries quad-COLUMN counts (zero segments omitted) + the note:
# lib.c `.v..`, helper.c/staged.c/untracked.c wt dirt, staged.c staged.
grep -qF '1 base, 3 wt, 1 staged' "$WORK/q.out" || {
    echo "--- quad status ---"; cat "$WORK/q.out"
    _fail "summary lacks the quad-column counts [1 base, 3 wt, 1 staged]"
}
grep -qF '(ahead 1)' "$WORK/q.out" || {
    echo "--- quad status ---"; cat "$WORK/q.out"
    _fail "summary lost the (ahead 1) note"
}
# no legacy bucket/divergence rows leak into the quad default
grep -qE ' (mod|unk|put|post) ' "$WORK/q.out" && {
    echo "--- quad status ---"; cat "$WORK/q.out"
    _fail "quad default still emits legacy bucket/divergence rows"
}

echo "ok   quad default: unified quad rows + column counts"
pass
