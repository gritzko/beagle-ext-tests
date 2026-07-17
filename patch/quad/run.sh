#!/bin/sh
#  test/patch/quad — BRO-030: the quad report is the DEFAULT `jab patch` per-file
#  report — unified quad rows (`<date7> <quad4> <path>`, wiki/Status.mkd) for the
#  touched set, replacing the legacy per-file `applied`/`merged` rows.  Fixture =
#  addmod's shape, absorbed via `?feat` (NEXT scope):
#
#       T0 ── T1          ← cur (trunk): T1 edits keep.txt line 1
#         \
#          F1             ← ?feat: F1 adds new.txt + edits keep.txt line 3
#
#  The clone pins `#<T1>` (detached ⇒ track = base = root), so keep.txt's
#  disjoint weave-merge reads `..vv` (ASCII canon) and the clean-added new.txt
#  `..oo`.  RED until the quad-default flip lands (today's default still prints
#  the legacy `applied`/`merged` rows) — intended TDD state.
. "$(dirname "$0")/../../lib/patchcase.sh"

# TEST-003 jab-only DAG via patchcase.sh helpers (bootstrap post-alone, absolute
# `?feat` fork, `_trunk` switch by pinned t0, keeper.idx drop per op).
build() {
    printf '1\n2\n3\n4\n' > keep.txt
    _boot 't0'                                  # bootstrap trunk @ t0
    _fork feat                                  # label feat @ t0
    _sw feat
    printf '1\n2\nTHREE\n4\n' > keep.txt        # theirs: line 3 (disjoint)
    printf 'brand new\n' > new.txt              # theirs: a new file
    _ci 'f1' keep.txt new.txt
    _trunk                                      # back to trunk @ t0
    printf 'ONE\n2\n3\n4\n' > keep.txt          # ours: line 1
    _ci 't1' keep.txt
}

ORG="$WORK/org"; mkdir -p "$ORG/.be"
_opwd=$(pwd); cd "$ORG"; build; cd "$_opwd"
rm -f "$ORG"/.be/*.keeper.idx 2>/dev/null
_ORGTIP=$(_orgtip "$ORG")

#  quad-default run (flagless): quad rows ARE the per-file report.
Q="$WORK/q"; mkdir -p "$Q"
( cd "$Q" && "$BE" get "file://$ORG/.be#$_ORGTIP" >/dev/null 2>&1 ) \
    || _fail "quad clone failed"
( cd "$Q" && "$JABC" patch '?feat' --plain ) \
    >"$WORK/q.out" 2>"$WORK/q.err" \
    || _fail "quad patch failed: $(cat "$WORK/q.err")"
grep -Fq ' ..vv keep.txt' "$WORK/q.out" \
    || _fail "no ..vv quad row for keep.txt: $(cat "$WORK/q.out")"
grep -Fq ' ..oo new.txt' "$WORK/q.out" \
    || _fail "no ..oo quad row for new.txt: $(cat "$WORK/q.out")"
grep -Eq 'applied|merged' "$WORK/q.out" \
    && _fail "legacy rows leaked into quad-default output" || true
pass
