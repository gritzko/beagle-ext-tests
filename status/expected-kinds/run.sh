#!/bin/sh
#  test/status/expected-kinds — STATUS-017 (DIS-080 §6): dirty stays wt != base;
#  the EXPECTED reading (base ⊕ the in-scope patch-ins, via the weave) only
#  SPLITS the dirt into kinds.  One absorb, both clean outcomes:
#
#       T0 ── T1          ← cur (trunk): T1 edits f-merge line 5
#         \
#          F1             ← ?feat: F1 edits f-take (only theirs), f-merge line 1
#
#  assert.js runs classify on the patched wt, then DESTROYS the DIS-057 stamps
#  (mtime only, bytes untouched) — the kinds must survive, proving the band is a
#  fast path and EXPECTED is the truth — then edits a patched file to `mod`.
. "$(dirname "$0")/../../lib/patchcase.sh"

build() {
    printf 'take a\ntake b\ntake c\n' > f-take.txt
    printf 'm1\nm2\nm3\nm4\nm5\n'     > f-merge.txt
    printf 'keep\n'                   > keep.txt
    _boot 't0'
    _fork feat
    _sw feat
    printf 'take a\nTHEIRS b\ntake c\n'   > f-take.txt    # only-theirs → pat
    printf 'M1-theirs\nm2\nm3\nm4\nm5\n'  > f-merge.txt   # theirs: line 1
    _ci 'f1 theirs' f-take.txt f-merge.txt
    F1=$(_tip feat); export F1
    _trunk
    printf 'm1\nm2\nm3\nm4\nM5-ours\n' > f-merge.txt      # ours: line 5 → mrg
    _ci 't1 ours' f-merge.txt
}

ORG="$WORK/org"; mkdir -p "$ORG/.be"
_opwd=$(pwd); cd "$ORG"; build; cd "$_opwd"
rm -f "$ORG"/.be/*/*.keeper.idx 2>/dev/null
_ORGTIP=$(_orgtip "$ORG")
JS="$WORK/js"; mkdir -p "$JS"
( cd "$JS" && "$BE" get "file://$ORG/.be#$_ORGTIP" >/dev/null 2>&1 ) || _fail "JS clone failed"

#  No conflicting file in this fixture — the absorb must exit 0.
( cd "$JS" && "$JABC" patch "#$F1" ) >"$WORK/js.out" 2>"$WORK/js.err" \
    || _fail "JS patch failed: $(cat "$WORK/js.err")"

"$JABC" "$_CASE/assert.js" "$JS" || _fail "assert.js: EXPECTED-kind invariant broken"

pass
