#!/bin/sh
#  test/patch/dirty-ours — BE-010: `be patch` must NOT clobber an UNCOMMITTED wt
#  edit.  On the commit side ours (trunk) == base (clean); theirs edits a
#  DISJOINT region.  But the wt carries an uncommitted line-1 edit.  The COMMIT-
#  only classifier would route this to the "only theirs" arm and clean-overwrite
#  the file with theirs bytes — losing the user's work.  The fix folds the wt's
#  on-disk bytes onto the OURS side of the weave, so both regions merge (`mrg`).
#
#       T0 ── (trunk, ours) : committed keep.txt = base  1/2/3/4
#         \                    wt on disk (uncommitted) : ONE/2/3/4  ← dirty edit
#          F1  (?feat, theirs): committed keep.txt = 1/2/THREE/4     ← disjoint
#
#  Assert keep.txt weaves BOTH the dirty line-1 edit AND theirs' line-3 edit,
#  status `mrg`, counted merged — never a silent take-theirs clobber.
. "$(dirname "$0")/../../lib/patchcase.sh"

build() {
    printf '1\n2\n3\n4\n' > keep.txt
    _boot 't0'                                  # bootstrap trunk @ t0 (base)
    _fork feat                                  # label feat @ t0
    _sw feat
    printf '1\n2\nTHREE\n4\n' > keep.txt        # theirs: line 3 (disjoint)
    _ci 'f1' keep.txt
    F1=$(_tip feat); export F1
    _trunk                                      # back to trunk @ t0 (keep.txt=base)
}

#  BE-010 custom parity: clone ONLY the JS wt (as patch_parity does), then DIRTY
#  keep.txt on disk WITHOUT committing, THEN patch — so the ours side is the wt's
#  uncommitted bytes.  (Standard patch_parity has no post-clone dirty hook.)
dirty_patch() {
    ORG="$WORK/org"; mkdir -p "$ORG/.be"
    _opwd=$(pwd); cd "$ORG"; build; cd "$_opwd"
    _f1=$F1
    rm -f "$ORG"/.be/*.keeper.idx 2>/dev/null
    JS="$WORK/js"; mkdir -p "$JS"
    ( cd "$JS" && "$BE" get "file://$ORG/.be" >/dev/null 2>&1 ) || _fail "JS clone failed"
    #  DIRTY the cloned wt: an uncommitted line-1 edit, DISJOINT from theirs' line 3.
    printf 'ONE\n2\n3\n4\n' > "$JS/keep.txt"
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
