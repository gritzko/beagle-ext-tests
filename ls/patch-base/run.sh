#!/bin/sh
#  test/ls/patch-base — PATCH-024: an in-scope `patch` row must NOT move the
#  base tree the listing classifies against.  Fixture:
#
#       T0 ── T1          ← cur (base): T1 adds ours.txt
#         \
#          F1             ← ?feat: keep.txt line 3 -> THREE
#
#  After `patch ?feat`, ours.txt is tracked by the BASE commit T1 (so it lists
#  `eq`) and keep.txt carries the patched-in bytes over T1's (so it lists `mod`).
#  RED before the fix: classifyDir read its baseline from wtlog.baselineTip(),
#  which the patch row moved to F1 — F1's tree has no ours.txt (`unk`) and its
#  keep.txt equals the wt bytes (`eq`).
. "$(dirname "$0")/../lib/lscase.sh"

W=$(new_wt patchbase)
cd "$W"

#  Local DAG helpers (the patchcase.sh shapes): the rolling `.keeper.idx` indexes
#  only the LATEST keeper, so drop it per op or the t0 fork point reads MISSING.
_jab() { rm -f .be/*/*.keeper.idx 2>/dev/null; "$BE" "$@" >/dev/null 2>&1; }
_tip() { "$JABC" refs 2>/dev/null | sed -n 's/^cur: *//p'; }

printf '1\n2\n3\n4\n' > keep.txt
_jab post 't0'                      # bootstrap trunk @ t0 (post alone, auto-adds)
BOOT=$(_tip)
_jab put '?feat'                    # label feat @ t0
_jab get '?feat'
printf '1\n2\nTHREE\n4\n' > keep.txt
_jab put keep.txt
_jab post 'f1'
_jab post '?feat'
_jab get "?#$BOOT"                  # back to t0
printf 'ours\n' > ours.txt
_jab put ours.txt
_jab post 't1'                      # THE BASE: tracks keep.txt(3) + ours.txt

"$JABC" patch '?feat' >"$WORK/patch.out" 2>"$WORK/patch.err" \
    || _fail "patch ?feat failed: $(cat "$WORK/patch.err")"
grep -q '^THREE$' keep.txt || _fail "fixture: patch did not land THREE in the wt"

"$JABC" ls 'ls:' >"$WORK/ls.out" 2>"$WORK/ls.err" || _fail "ls failed: $(cat "$WORK/ls.err")"
grep -Eq ' unk +ours\.txt$' "$WORK/ls.out" \
    && { cat "$WORK/ls.out"; _fail "ours.txt is tracked by the BASE commit — never unk"; }
grep -Eq ' eq +ours\.txt$' "$WORK/ls.out" \
    || { cat "$WORK/ls.out"; _fail "ours.txt should list eq (clean, base-tracked)"; }
grep -Eq ' mod +keep\.txt$' "$WORK/ls.out" \
    || { cat "$WORK/ls.out"; _fail "keep.txt carries patched-in bytes over the base — mod" ; }
echo "ok   ls: base-tracked file stays tracked with a patch row in scope"

pass
