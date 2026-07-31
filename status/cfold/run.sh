#!/bin/sh
#  test/status/cfold — CFOLD-001 repro: the EXPECTED reading of a patched wt
#  must cost O(the changes above the LCA), NOT O(paths x whole ancestry x tree).
#
#       T0 ── O1 ── O2 ── O3 ── … ── O16      ← trunk (ours)
#         \            ^SHALLOW      ^DEEP
#          F1                                 ← ?feat: edits f1..f4 + both.txt
#
#  Two clones of the SAME store — one pinned 4 commits above the fork, one 17
#  above — get the SAME `patch #F1` absorbed.  The trunk commits O2.. touch
#  ONLY deep/dir/noise.txt, so nothing the patch touches changes between the
#  two tips: every extra commit is pure ANCESTRY.  `JAB_STATS=1 jab status`
#  prints the object-read / weave-fold counters (shared/util/stats.js) and the
#  case asserts the DEEP-minus-SHALLOW growth is a small per-commit residue,
#  never the paths x ancestry x tree-size term.
#
#  RED before the fix (13 extra commits, 5 patch-touched paths):
#      shallow  obj=207 blob=25 fold=11 merge=5
#      deep     obj=662 blob=90 fold=11 merge=5   → +35 obj +5 blobs per commit
#  GREEN after: shallow obj=53 blob=11 fold=3, deep obj=79 blob=11 fold=3 —
#  +2 obj (the commit + its root tree), ZERO extra blobs/folds per commit.
#  Both wts' status rows are golden-asserted (byte-parity, patched tree) and
#  must be IDENTICAL to each other — the dirt does not depend on ancestry depth.
. "$(dirname "$0")/../../lib/patchcase.sh"

N=16                                   # trunk commits above the fork
SHALLOW_AT=3                           # the shallow clone's tip (O3)

#  Leaner than patchcase's _ci for the noise run: no branch republish (the
#  trunk tip is read straight off the wt's own cur), 2 jab spawns per commit.
_noise() { _jab put "$2" >/dev/null 2>&1; _jab post "$1" >/dev/null 2>&1; }

build() {
    for f in f1 f2 f3 f4; do printf 'a\nb\nc\nd\ne\n' > "$f.txt"; done
    printf 'B1\nB2\nB3\nB4\nB5\n' > both.txt
    mkdir -p deep/dir
    printf 'noise 0\n' > deep/dir/noise.txt
    _boot 't0'
    _fork feat
    _sw feat
    #  theirs: f1..f4 line 3 (ours never touches them → pat) + both.txt line 1.
    for f in f1 f2 f3 f4; do printf 'a\nb\nTHEIRS\nd\ne\n' > "$f.txt"; done
    printf 'THEIRS-B1\nB2\nB3\nB4\nB5\n' > both.txt
    _ci 'f1 theirs' f1.txt f2.txt f3.txt f4.txt both.txt
    F1=$(_tip feat); export F1
    _trunk
    #  ours: ONE disjoint edit on both.txt (→ a real 3-way weave, `mrg`), then
    #  pure-ancestry commits that touch only deep/dir/noise.txt.
    printf 'THEIRS-B1\nB2\nB3\nB4\nOURS-B5\n' > /dev/null   # (doc: theirs side)
    printf 'B1\nB2\nB3\nB4\nOURS-B5\n' > both.txt
    printf 'noise 1\n' > deep/dir/noise.txt
    _jab put both.txt deep/dir/noise.txt >/dev/null 2>&1
    _jab post 'o1' >/dev/null 2>&1
    i=2
    while [ "$i" -le "$N" ]; do
        printf 'noise %s\n' "$i" > deep/dir/noise.txt
        _noise "o$i" deep/dir/noise.txt
        [ "$i" = "$SHALLOW_AT" ] && { SHALLOW=$(_tip .); export SHALLOW; }
        i=$((i+1))
    done
    DEEP=$(_tip .); export DEEP
}

ORG="$WORK/org"; mkdir -p "$ORG/.be"
_opwd=$(pwd); cd "$ORG"; build; cd "$_opwd"
[ -n "${SHALLOW:-}" ] && [ -n "${DEEP:-}" ] || _fail "builder did not export SHALLOW/DEEP"
rm -f "$ORG"/.be/*.keeper.idx 2>/dev/null

#  _clone WTDIR TIP — clone pinned at TIP, absorb the SAME `patch #F1`.
_clone() {
    mkdir -p "$1"
    ( cd "$1" && "$BE" get "file://$ORG/.be#$2" >/dev/null 2>&1 ) || _fail "clone at $2 failed"
    ( cd "$1" && "$JABC" patch "#$F1" ) >"$WORK/patch.out" 2>"$WORK/patch.err" \
        || _fail "patch failed: $(cat "$WORK/patch.err")"
}
A="$WORK/shallow"; B="$WORK/deep"
_clone "$A" "$SHALLOW"
_clone "$B" "$DEEP"

#  _stats WTDIR KEY — the counter KEY off `JAB_STATS=1 jab status` (fd 2).
_stats() {
    ( cd "$1" && JAB_STATS=1 "$JABC" status --plain ) 2>"$WORK/$(basename "$1").err" >/dev/null
    sed -n 's/^stats: //p' "$WORK/$(basename "$1").err" \
      | tr ' ' '\n' | sed -n "s/^$2=//p"
}
for k in obj commit tree blob fold merge; do
    eval "A_$k=\$(_stats \"\$A\" $k)"; eval "B_$k=\$(_stats \"\$B\" $k)"
done
[ -n "${A_obj:-}" ] && [ -n "${B_obj:-}" ] || _fail "no stats line (JAB_STATS hook missing)"
echo "cfold: shallow obj=$A_obj commit=$A_commit tree=$A_tree blob=$A_blob fold=$A_fold merge=$A_merge" >&2
echo "cfold: deep    obj=$B_obj commit=$B_commit tree=$B_tree blob=$B_blob fold=$B_fold merge=$B_merge" >&2

#  --- the CFOLD-001 assertions ------------------------------------------
#  0. byte-parity FIRST: both trees' status rows are IDENTICAL (the dirt does
#     not depend on ancestry depth) and match the golden snapshotted from the
#     pre-CFOLD-001 full-history reading.
_rows() { _jstatus "$1"; echo "=== buckets ==="; "$JABC" "$_CASE/buckets.js" "$1"; }
_rows "$A" >"$WORK/a.rows"; _rows "$B" >"$WORK/b.rows"
cmp -s "$WORK/a.rows" "$WORK/b.rows" \
    || { diff "$WORK/a.rows" "$WORK/b.rows" >&2; _fail "status rows differ shallow vs deep"; }
golden_assert "$NAME" "$GOLDEN" <"$WORK/b.rows"

DC=$((N - SHALLOW_AT))                 # extra ancestry commits (13), 0 extra changes
#  1. blob reads are O(changes): the extra ancestry re-inflates NOTHING.
#     (RED: ~5 blobs per extra commit — one per patch-touched path.)
[ $((B_blob - A_blob)) -le 8 ] \
    || _fail "blob reads scale with ancestry: +$((B_blob - A_blob)) over $DC pure-ancestry commits"
#  2. weave folds/merges are O(changes), flat in ancestry.
[ $((B_fold - A_fold)) -le 2 ] || _fail "folds scale with ancestry: +$((B_fold - A_fold))"
[ $((B_merge - A_merge)) -le 2 ] || _fail "merges scale with ancestry: +$((B_merge - A_merge))"
[ "$B_fold" -le 24 ] || _fail "fold count $B_fold is not O(changes)"
#  3. object reads keep at most a small per-commit residue (the BLAME-001
#     "one root-tree read per changed-tree commit" floor), never paths x tree.
[ $((B_obj - A_obj)) -le $((4 * DC)) ] \
    || _fail "object reads scale as paths x ancestry: +$((B_obj - A_obj)) over $DC commits"

pass
