#!/bin/sh
#  test/patch/stacked-conflict — DIS-080/PATCH-025: TWO stacked `patch` runs
#  over the SAME conflicted line.  Run 1 conflicts; per DIS-080 its output is
#  the RGA live reading of the merged weave (both sides' tokens in weave order,
#  NO `<<<<`/`||||`/`>>>>`), so the file stays tokenizable and re-weavable and
#  run 2 folds it as ordinary content — the driving case fences broke.
#
#       T0 ── T1              ← cur (trunk): T1 sets line 2 = Y
#         \ \
#          \ F2               ← ?feat2: F2 sets line 2 = Z
#           F1                ← ?feat1: F1 sets line 2 = X
#
#  Run 1 (`#F1`) conflicts X vs Y; run 2 (`#F2`) weaves Z into the SAME anchor
#  over run 1's bytes.  Both exit NON-ZERO (PATCHCONFLICT), both land a durable
#  `con f.txt` row, and the final bytes carry all three sides with NO fences —
#  under the old fenced render run 2 nested a wider fence around run 1's.
. "$(dirname "$0")/../../lib/patchcase.sh"

# TEST-003 jab-only DAG via patchcase.sh helpers (bootstrap post-alone, absolute
# `?feat` fork, `_trunk` switch by pinned t0, keeper.idx drop per op).
build() {
    printf 'a\nb\nc\n' > f.txt
    _boot 't0'
    _fork feat1
    _sw feat1
    printf 'a\nX\nc\n' > f.txt           # theirs 1: line 2 = X
    _ci 'f1 line2=X' f.txt
    F1=$(_tip feat1); export F1
    _trunk
    _fork feat2
    _sw feat2
    printf 'a\nZ\nc\n' > f.txt           # theirs 2: line 2 = Z
    _ci 'f2 line2=Z' f.txt
    F2=$(_tip feat2); export F2
    _trunk
    printf 'a\nY\nc\n' > f.txt           # ours: line 2 = Y
    _ci 't1 line2=Y' f.txt
}

#  Two absorptions into ONE clone (patch_parity runs a single one), then ONE
#  golden stream over both banners + the final status + the stacked bytes.
stacked_patch() {
    ORG="$WORK/org"; mkdir -p "$ORG/.be"
    _opwd=$(pwd); cd "$ORG"; build; cd "$_opwd"
    rm -f "$ORG"/.be/*.keeper.idx 2>/dev/null
    #  DIS-076: default clone = the WORKTREE, pinned at its OWN cur.
    _ORGTIP=$(_orgtip "$ORG")
    JS="$WORK/js"; mkdir -p "$JS"
    ( cd "$JS" && "$BE" get "file://$ORG/.be#$_ORGTIP" >/dev/null 2>&1 ) \
        || _fail "JS clone failed"
    PATCH_EXPECT=conflict
    _run_patch "$JS" "#$F1"
    mv "$WORK/js.out" "$WORK/js1.out"
    if grep -q '<<<<' "$JS/f.txt"; then _fail "run 1 wrote conflict fences"; fi
    _run_patch "$JS" "#$F2"
    if grep -q '<<<<' "$JS/f.txt"; then _fail "run 2 wrote conflict fences"; fi
    #  the durable con row is the conflict signal now — one per run.
    _cons=$(grep -ac "$(printf '\tcon\t')" "$JS/.be" 2>/dev/null || echo 0)
    [ "$_cons" -ge 1 ] || _fail "no durable 'con f.txt' row after the stack"
    {
        echo "=== run 1 ==="; cat "$WORK/js1.out"
        echo "=== run 2 ==="; cat "$WORK/js.out"
        echo "=== status ==="; _jstatus "$JS"
        echo "=== file bytes ==="; _fbytes "$JS" f.txt
    } | golden_assert "$NAME" "$GOLDEN"
}
stacked_patch
pass
