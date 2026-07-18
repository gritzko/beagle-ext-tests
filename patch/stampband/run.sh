#!/bin/sh
#  test/patch/stampband — PATCH-013: every file a patch AFFECTS carries the
#  patch row's DIS-057 band slot as its mtime (ceil-2ms pat / ceil-1ms mrg /
#  ceil cnf), unaffected files keep theirs byte-for-byte, and status reads the
#  outcome from the stamp with NO content read on clean applies.  One patch,
#  ALL outcome classes: clean take-theirs (top + subdir), weave merge, true
#  conflict, take-theirs ADD (file + subdir + symlink).  assert.js checks the
#  band against the PERSISTED patch row via ulog.ronStepMs + io.lstat, then
#  runs classify with an io.open hook (zero reads on the pat class).
. "$(dirname "$0")/../../lib/patchcase.sh"

#  TEST-003 jab-only DAG via patchcase.sh helpers.
#       T0 ── T1          ← cur (trunk): edits f-merge(l5)/f-conf(l2)/own.txt
#         \
#          F1             ← ?feat: edits f-take/f-merge(l1)/f-conf(l2)/sub/f-deep,
#                                  adds f-add.txt, sub/f-newadd.txt, slink
build() {
    mkdir -p sub
    printf 'take a\ntake b\ntake c\n'  > f-take.txt
    printf 'm1\nm2\nm3\nm4\nm5\n'      > f-merge.txt
    printf 'c1\nc2\nc3\n'              > f-conf.txt
    printf 'deep a\ndeep b\n'          > sub/f-deep.txt
    printf 'own\n'                     > own.txt
    printf 'keep\n'                    > keep.txt
    _boot 't0'
    _fork feat
    _sw feat
    printf 'take a\nTHEIRS b\ntake c\n'   > f-take.txt        # only-theirs edit
    printf 'M1-theirs\nm2\nm3\nm4\nm5\n'  > f-merge.txt       # theirs: line 1
    printf 'c1\nX-theirs\nc3\n'           > f-conf.txt        # theirs: line 2 = X
    printf 'deep a\nDEEP-theirs\n'        > sub/f-deep.txt    # only-theirs, subdir
    printf 'added by theirs\n'            > f-add.txt         # base-absent ADD
    printf 'new deep\n'                   > sub/f-newadd.txt  # ADD in a subdir
    ln -s f-merge.txt slink                                   # ADD symlink; a
    _ci 'f1 theirs' f-take.txt f-merge.txt f-conf.txt \
        sub/f-deep.txt f-add.txt sub/f-newadd.txt slink       # follow would hit
    F1=$(_tip feat); export F1                                # f-merge's slot
    _trunk
    printf 'm1\nm2\nm3\nm4\nM5-ours\n' > f-merge.txt          # ours: line 5 → mrg
    printf 'c1\nY-ours\nc3\n'          > f-conf.txt           # ours: line 2 = Y → cnf
    printf 'own edited\n'              > own.txt              # ours-only file
    _ci 't1 ours' f-merge.txt f-conf.txt own.txt
}

ORG="$WORK/org"; mkdir -p "$ORG/.be"
_opwd=$(pwd); cd "$ORG"; build; cd "$_opwd"
rm -f "$ORG"/.be/*.keeper.idx 2>/dev/null
_ORGTIP=$(_orgtip "$ORG")
JS="$WORK/js"; mkdir -p "$JS"
( cd "$JS" && "$BE" get "file://$ORG/.be#$_ORGTIP" >/dev/null 2>&1 ) || _fail "JS clone failed"

#  (c) unaffected files keep their mtimes byte-for-byte (ns) across the patch.
own_pre=$(stat -c '%y' "$JS/own.txt"); keep_pre=$(stat -c '%y' "$JS/keep.txt")

#  PATCH.mkd 2026-07-17: the cnf fixture file makes patch exit NON-ZERO (loud
#  conflict); a crash (any other non-zero) still fails — assert.js is the gate.
_rc=0; ( cd "$JS" && "$JABC" patch "#$F1" ) >"$WORK/js.out" 2>"$WORK/js.err" || _rc=$?
[ "$_rc" = 0 ] || grep -q PATCHCONFLICT "$WORK/js.err" \
    || _fail "JS patch failed: $(cat "$WORK/js.err")"

[ "$(stat -c '%y' "$JS/own.txt")"  = "$own_pre" ]  || _fail "patch touched own.txt's mtime"
[ "$(stat -c '%y' "$JS/keep.txt")" = "$keep_pre" ] || _fail "patch touched keep.txt's mtime"

#  (a)+(b): band mtimes off the persisted row + stamp-read-back + zero reads.
"$JABC" "$_CASE/assert.js" "$JS" || _fail "assert.js: band/classify invariant broken"

pass
