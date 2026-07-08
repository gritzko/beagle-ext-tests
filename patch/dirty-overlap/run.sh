#!/bin/sh
#  test/patch/dirty-overlap — BE-010: a dirty wt edit that OVERLAPS theirs must
#  report a CONTENT CONFLICT (`cnf`, fence markers), never a silent clobber.
#  Mirrors native's overlap case: committed ours == base (clean), the wt carries
#  an uncommitted line-3 edit, and theirs rewrites the SAME line-3 differently —
#  a true overlap the 3-way weave fences with `<<<<`/`||||`/`>>>>`.
#
#       T0 ── (trunk, ours) : committed keep.txt = base  1/2/3/4
#         \                    wt on disk (uncommitted) : 1/2/OURS/4  ← dirty
#          F1  (?feat, theirs): committed keep.txt = 1/2/THEIRS/4     ← same line
#
#  Assert keep.txt fences the collision (`cnf`), the dirty bytes are NOT lost.
. "$(dirname "$0")/../../lib/patchcase.sh"

build() {
    printf '1\n2\n3\n4\n' > keep.txt
    _boot 't0'                                  # bootstrap trunk @ t0 (base)
    _fork feat                                  # label feat @ t0
    _sw feat
    printf '1\n2\nTHEIRS\n4\n' > keep.txt       # theirs: line 3 = THEIRS
    _ci 'f1' keep.txt
    F1=$(_tip feat); export F1
    _trunk                                      # back to trunk @ t0 (keep.txt=base)
}

#  BE-010 custom parity (see dirty-ours): clone the JS wt, DIRTY keep.txt line 3
#  WITHOUT committing (OVERLAPS theirs' line 3), THEN patch.
dirty_patch() {
    ORG="$WORK/org"; mkdir -p "$ORG/.be"
    _opwd=$(pwd); cd "$ORG"; build; cd "$_opwd"
    _f1=$F1
    rm -f "$ORG"/.be/*.keeper.idx 2>/dev/null
    JS="$WORK/js"; mkdir -p "$JS"
    ( cd "$JS" && "$BE" get "file://$ORG/.be" >/dev/null 2>&1 ) || _fail "JS clone failed"
    #  DIRTY the cloned wt: an uncommitted line-3 edit that COLLIDES with theirs.
    printf '1\n2\nOURS\n4\n' > "$JS/keep.txt"
    ( cd "$JS" && "$JABC" patch "#$_f1" ) >"$WORK/js.out" 2>"$WORK/js.err" \
        || _fail "JS patch failed: $(cat "$WORK/js.err")"
    {
        echo "=== stdout ==="; cat "$WORK/js.out"
        echo "=== patch row ==="; _patch_row "$JS"
        echo "=== status ==="; _jstatus "$JS"
        echo "=== file bytes ==="; _fbytes "$JS" keep.txt
    } | golden_assert "$NAME" "$GOLDEN"
}
dirty_patch
pass
