#!/bin/sh
#  DIFF-021: a con-path diff must keep its DIFF-020 provenance when emitDiff and
#  the DIS-082 cursor walk disagree on TOKEN GRANULARITY.  Both sides edit ONE
#  comment line: theirs edits the word next to the prefix, ours RE-TYPES the
#  prefix (`//  ` -> `/ `) — the merge conflicts, and the fold aligns ours' `/`
#  against the base's `//` atom, SPLITTING it: the cursor walk reads the dead
#  opener as ONE `//` atom while emitDiff emits TWO `/` toks.  markRecord's old
#  token-text zip could then never fit its window (record N+1 toks vs N atoms),
#  so the WHOLE record lost bit 26 and the diff washed as a plain local edit.
#  Alignment is by BYTE OFFSETS now (both walks agree on the byte extents):
#   -  --tlv MUST carry TOK_PATCHED (bit 26) toks (check.js counts them);
#   -  --color MUST paint the theirs washes (lime 155 in, pale orange 215 rm)
#      off the MARKED record (DIFF-021's second arm: the render was fed the
#      unmarked original before);
#   -  --plain stays byte-identical (provenance is a COLOUR distinction only).
. "$(dirname "$0")/../lib/diffcase.sh"

W=$(new_wt g)
cd "$W"

_jab() { rm -f .be/*/*.keeper.idx 2>/dev/null; "$BE" "$@" >/dev/null 2>&1; }
_tip() { "$JABC" refs 2>/dev/null | sed -n 's/^cur: *//p'; }
cq()  { grep -q "48;5;$1" "$WORK/j.color" || _fail "$2 (expected 256-bg $1)"; }

printf '//  alpha beta gamma\nfunction f() {\n  return 1;\n}\n' > f.js
_jab post 't0'
BOOT=$(_tip)
_jab put '?feat'
_jab get '?feat'
printf '//  ALPHA beta gamma\nfunction f() {\n  return 1;\n}\n' > f.js
_jab put f.js
_jab post 'f1'
F1=$(_tip)
_jab get "?#$BOOT"                  # back to t0 — the pre-merge base
grep -q '^//  alpha' f.js || _fail "fixture: base wt should carry the //  prefix"

#  ours re-types the line's PREFIX (dirty, uncommitted): `//  ` becomes `/ `.
printf '/ alpha beta gamma\nfunction f() {\n  return 1;\n}\n' > f.js
"$JABC" get "?#$F1" >"$WORK/get.out" 2>"$WORK/get.err" || true
grep -q 'merged with conflicts' "$WORK/get.err" "$WORK/get.out" \
    || { cat "$WORK/get.err"; _fail "get: no conflict report"; }
grep -q 'ALPHA' f.js || _fail "fixture: merge lost the theirs edit"
grep -q '^/ ' f.js || _fail "fixture: merge lost the ours prefix"

#  bit-26 survival in the on-wire stream: the pre-fix zip dropped EVERY
#  provenance bit for the record (probe: 7 changed, 0 patched).
"$JABC" diff f.js --tlv >"$WORK/diff.tlv" 2>"$WORK/tlv.err" \
    || { cat "$WORK/tlv.err"; _fail "jab diff --tlv failed"; }
[ -s "$WORK/diff.tlv" ] || _fail "jab diff --tlv emitted ZERO bytes"
"$JABC" "$_CASE/check.js" "$WORK/diff.tlv" >"$WORK/check.out" 2>&1 \
    || { cat "$WORK/check.out"; _fail "check.js failed"; }
grep -q 'test/diff/24-con-split-provenance OK' "$WORK/check.out" \
    || { cat "$WORK/check.out"; _fail "check.js did not report OK"; }

#  the 4-wash render survives the split: theirs lime/orange + ours salad/salmon.
diff_eq "con diff across a split dead token" 'diff:f.js'
have '^\+/ ALPHA beta gamma$' "conflict: the merged line shows as the in side"
have '^-//  alpha beta gamma$' "conflict: the pre-merge base line shows as rm"
cq 155 "conflict: the theirs insertion washes lime"
cq 215 "conflict: the theirs removal washes pale orange"
cq 157 "conflict: the ours insertion washes salad"
cq 217 "conflict: the ours removal washes salmon"

pass
