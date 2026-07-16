#!/bin/sh
#  test/patch/tree-nav — DIS-076: `jab patch //X` absorbs ANOTHER worktree
#  addressed by a scheme-less NAV operand (not `file:<path>`, see tree-uri).
#  patch.js's resolveSource resolves `//X` THROUGH resolve_hash (RULE ZERO:
#  core/resolve_hash.js step 5.5 = X's own cur tip) — never a hand-rolled
#  wtlog.open(x).curTip().  Reaching the verb argv at all also needs
#  core/loop.js's authorityRepo "operand vs context" classifier (DIS-062);
#  this case is the end-to-end proof both halves now compose.
#
#       T0 ── X1          ← X: one commit ahead (disjoint edit, line 3)
#       T0                ← Y: stays put; `patch //X` absorbs X1 cleanly
. "$(dirname "$0")/../../lib/patchcase.sh"

# `//X`/`//Y` need a PROJECT ROOT's `work/` dir (rs_work_root) — unlike every
# other test/patch/* case's flat scratch wt (pattern: test/bro/ticket).
PROJ="$WORK/proj"
WORKD=$(rs_work_root "$PROJ")            # $PROJ/work — where `//NAME` resolves

cd "$PROJ"
printf 'a\nb\nc\nd\ne\n' > f.txt
rm -f .be/*.keeper.idx 2>/dev/null
"$BE" post 't0' >/dev/null 2>&1 || _fail "origin bootstrap failed"
# DIS-073 wave: a bare post no longer advances any ref (unrelated red wave,
# untouched here) — mint an EXPLICIT `?trunk` label so the clones below have
# a real ref to resolve, sidestepping that unrelated breakage entirely.
"$BE" put '?trunk' >/dev/null 2>&1 || _fail "origin ?trunk label failed"
cd "$WORK"

# Two secondary worktrees UNDER work/ (store-backed clones off PROJ, mirrors
# tree-uri's W1/W2) so `//X`/`//Y` resolve to them.
_proj_jab() { _d=$1; shift; rm -f "$PROJ"/.be/*.keeper.idx 2>/dev/null; ( cd "$_d" && "$BE" "$@" ); }
mkdir -p "$WORKD/X" "$WORKD/Y"
_proj_jab "$WORKD/X" get "file://$PROJ/.be?trunk" >/dev/null 2>&1 || _fail "X clone failed"
_proj_jab "$WORKD/Y" get "file://$PROJ/.be?trunk" >/dev/null 2>&1 || _fail "Y clone failed"

# X grows ONE commit ahead (disjoint edit, line 3); Y stays at T0.
printf 'a\nb\nC\nd\ne\n' > "$WORKD/X/f.txt"
_proj_jab "$WORKD/X" put f.txt >/dev/null 2>&1 || _fail "X put failed"
_proj_jab "$WORKD/X" post 'x1 line3' >/dev/null 2>&1 || _fail "X post failed"

# THE REPRO: from Y, `patch //X` weave-merges X1 in (clean take-theirs: Y
# never touched f.txt).  Not `file:../X` — a bare scheme-less nav authority.
rm -f "$PROJ"/.be/*.keeper.idx 2>/dev/null
( cd "$WORKD/Y" && "$JABC" patch '//X' ) >"$WORK/js.out" 2>"$WORK/js.err" \
    || _fail "tree-nav patch failed: $(cat "$WORK/js.err")"

{
    echo "=== stdout ===";    cat "$WORK/js.out"
    echo "=== patch row ==="; _patch_row "$WORKD/Y"
    echo "=== status ===";    _jstatus "$WORKD/Y"
    echo "=== file bytes ==="; _fbytes "$WORKD/Y" f.txt
} | golden_assert "$NAME" "$GOLDEN"
pass
