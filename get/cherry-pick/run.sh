#!/bin/sh
# test/get/cherry-pick — GET-047 × GET.mkd 2.5: `get //WORK/path/file.c`
# cherry-picks ONE file from another worktree's rev into the current wt (spec
# marks it "an optional feature").  UNREGISTERED (.broken): at fe042740 the
# rpath does NOT narrow the get — `get //srcwt/ticket.txt` moves the WHOLE
# tree to //srcwt's tip (an unrelated readme.txt edit rides in, exit 0) and
# re-tracks the wt as `get//srcwt/ticket.txt#<srcwt tip>` (handleWtSeed always
# fans out the whole tree).  Optional-feature gap captured for GET-047.
. "$(dirname "$0")/../../lib/getrepro.sh"

# URI-016: bound the project-root climb (the get/wt-operand fixture pattern):
# ONE project root carrying the store, worktrees under work/, `//X` = work/X.
export BE_ROOT="$WORK"
PROJ="$WORK/proj"
mkdir -p "$PROJ/.be" "$PROJ/work"
printf 'readme\n' > "$PROJ/readme.txt"
( cd "$PROJ" && "$BE" post 'main tree' ) >/dev/null 2>&1 || _fail "seed failed"
MAIN=$(gr_tip_sha "$PROJ")
[ -n "$MAIN" ] || _fail "no main-tree tip"

# //srcwt advances TWO paths off the shared store — edits readme.txt AND adds
# ticket.txt — so a true single-file pick is tellable from a whole-tree switch.
SW="$PROJ/work/srcwt"; mkdir -p "$SW"
( cd "$SW" && "$JABC" get "file:$PROJ/.be#$MAIN" ) >/dev/null 2>&1 \
    || _fail "srcwt clone failed"
( cd "$SW" && printf 'README-EDITED\n' > readme.txt \
    && printf 'ticket work\n' > ticket.txt \
    && "$JABC" put readme.txt ticket.txt && "$JABC" post 'tw' ) >/dev/null 2>&1 \
    || _fail "srcwt advance failed"

# mywt: a sibling worktree still at the main baseline.
MW="$PROJ/work/mywt"; mkdir -p "$MW"
( cd "$MW" && "$JABC" get "file:$PROJ/.be#$MAIN" ) >/dev/null 2>&1 \
    || _fail "mywt clone failed"

rc=$(gr_jget "$MW" '//srcwt/ticket.txt')
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "cherry-pick get exit=$rc"; }
gr_file_is "$MW/ticket.txt" "ticket work"    # the picked file lands (HOLDS)

# SPEC 2.5: ONLY the named file is picked — the rest of the wt stays at its
# own baseline.  FAILS today: readme.txt arrives README-EDITED (a whole-tree
# move to srcwt's tip, not a scoped pick).
gr_file_is "$MW/readme.txt" "readme"

pass
