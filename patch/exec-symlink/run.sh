#!/bin/sh
#  test/js/patch/exec-symlink — `bin/patch.js` cherry-pick where theirs adds
#  an EXEC blob and a SYMLINK (JS-052).  Exercises checkout.materialise's
#  exec-bit chmod + symlink branches through the patch write path.
#
#       T0 ── T1          ← cur (trunk): T1 edits plain.txt
#         \
#          F1             ← ?feat: F1 adds run.sh (exec) + link -> plain.txt
#
#  Asserts the exec bit and symlink target survive identically to native
#  (cmp follows the symlink target bytes; the exec mode shows via be-status).
. "$(dirname "$0")/../../lib/patchcase.sh"

build() {
    printf 'hello\n' > plain.txt
    "$BE" put plain.txt >/dev/null 2>&1; "$BE" post 't0' >/dev/null 2>&1
    "$BE" put '?./feat' >/dev/null 2>&1
    "$BE" get '?..' >/dev/null 2>&1
    printf 'HELLO\n' > plain.txt
    "$BE" put plain.txt >/dev/null 2>&1; "$BE" post 't1' >/dev/null 2>&1
    "$BE" get '?feat' >/dev/null 2>&1
    printf '#!/bin/sh\necho hi\n' > run.sh; chmod 0755 run.sh
    ln -s plain.txt link
    "$BE" put run.sh link >/dev/null 2>&1; "$BE" post 'f1 add exec + symlink' >/dev/null 2>&1
    F1=$(grep -a $'\tpost\t' .be/org/refs | grep -oE '[0-9a-f]{40}' | tail -1)
    export F1
    "$BE" get '?..' >/dev/null 2>&1
}

# DIS-057: JS-only goldens (patch verb untied from native be).  theirs adds an
# exec blob (run.sh) + a symlink (link) — both clean take-theirs ADDs.  ours-only
# modified plain.txt, which the patch does NOT touch (theirs==fork there), so the
# wt's plain.txt stays at OURS' content.  RULING 2026-06-29: base is OURS (curTip)
# and theirs is a SEPARATE input — so run.sh + link read `pat` (clean take-theirs
# adds, absent from ours), while plain.txt (wt == ours-base) is clean `ok`
# (count-only, no row).  The old golden's `mod plain.txt` was the baselineTip-
# folds-theirs bug (ours-edited plain.txt != the theirs baseline).  Render order:
# pat rows, lex (link before run.sh).
EXPECT_BANNER='applied link\nmod plain.txt\napplied run.sh'; export EXPECT_BANNER
EXPECT_STATUS='pat link\npat run.sh'; export EXPECT_STATUS
patch_parity build '#@F1' plain.txt run.sh

#  Extra checks beyond patch_parity: the exec bit + symlink target on the JS
#  side match native exactly.
nx=$(ls -l "$WORK/nat/run.sh" | cut -c1-10); jx=$(ls -l "$WORK/js/run.sh" | cut -c1-10)
[ "$nx" = "$jx" ] || _fail "run.sh mode differs: native=$nx js=$jx"
nl=$(readlink "$WORK/nat/link" 2>/dev/null); jl=$(readlink "$WORK/js/link" 2>/dev/null)
[ "$nl" = "$jl" ] || _fail "link target differs: native=$nl js=$jl"
pass
