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

# TEST-003 jab-only DAG via patchcase.sh helpers (bootstrap post-alone, absolute
# `?feat` fork, `_trunk` switch by pinned t0, keeper.idx drop per op).
build() {
    printf 'hello\n' > plain.txt
    _boot 't0'
    _fork feat
    _sw feat
    printf '#!/bin/sh\necho hi\n' > run.sh; chmod 0755 run.sh
    ln -s plain.txt link
    _ci 'f1 add exec + symlink' run.sh link
    F1=$(_tip feat); export F1
    _trunk
    printf 'HELLO\n' > plain.txt
    _ci 't1' plain.txt
}

# JAB-003 golden snapshot (native oracle retired): run.sh + link are clean
# take-theirs ADDs (`pat`); the golden captures the exec bit + symlink target
# via _fbytes, folding the ex-native mode/target checks into one snapshot.
patch_parity build '#@F1' link plain.txt run.sh
pass
