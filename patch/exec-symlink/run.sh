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

# JAB-003 golden snapshot (native oracle retired): run.sh + link are clean
# take-theirs ADDs (`pat`); the golden captures the exec bit + symlink target
# via _fbytes, folding the ex-native mode/target checks into one snapshot.
patch_parity build '#@F1' link plain.txt run.sh
pass
