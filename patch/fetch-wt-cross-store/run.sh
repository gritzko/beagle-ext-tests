#!/bin/sh
#  test/patch/fetch-wt-cross-store — PATCH-011 (the live case): `jab patch
#  file:<wt-path>` where the addressed WORKTREE anchors ANOTHER store and its
#  cur tip sits on a NON-TRUNK branch.  patch follows the wt's `.be` store
#  redirect (GET-038), fetches the wt's CUR TIP closure from THAT store into
#  the local shard (objects only — the PATCH-011 fetch leg), then absorbs
#  all-local (theirs = the wt's cur tip, PATCH-010 tree semantics).
#
#      store s1:  t0 ── F1 (?feat)   ← wt A (secondary, cur = ?feat @ F1)
#      store s2:  t0 ── b1 (trunk)   ← wt B (primary) runs `patch file:<A>`
#
#  The two stores share t0 BY CONSTRUCTION (the pinned SOURCE_DATE_EPOCH clock
#  makes identical build steps mint identical shas — no wire clone needed).
. "$(dirname "$0")/../../lib/patchcase.sh"

#  Store s1 + its secondary wt A on ?feat, ONE commit ahead (F1 edits line 3).
S1="$WORK/s1"; mkdir -p "$S1/.be"
cd "$S1"
printf 'a\nb\nc\n' > f.txt
_boot 't0'
_fork feat
#  TEST-003 rolling-idx quirk: drop s1's stale keeper.idx before each op.
_s1_jab() { _d=$1; shift; rm -f "$S1"/.be/*.keeper.idx; ( cd "$_d" && "$BE" "$@" ); }
#  DIS-076: default clone = the WORKTREE, pinned at its OWN cur (no ref needed
#  — a bare post never mints one).
S1_TIP=$(_orgtip "$S1")
A="$WORK/A"; mkdir -p "$A"
_s1_jab "$A" get "file://$S1/.be#$S1_TIP" >/dev/null 2>&1 || _fail "A clone failed"
_s1_jab "$A" get '?feat' >/dev/null 2>&1 || _fail "A get ?feat failed"
printf 'a\nb\nC\n' > "$A/f.txt"
_s1_jab "$A" put f.txt >/dev/null 2>&1 || _fail "A put failed"
_s1_jab "$A" post 'f1 line3' >/dev/null 2>&1 || _fail "A post failed"

#  Store s2 (an INDEPENDENT primary wt B): the SAME t0 by construction, then
#  its own line-1 edit — s2's shard lacks F1, and F1 is NOT s1's trunk tip.
B="$WORK/b"; mkdir -p "$B/.be"
cd "$B"
printf 'a\nb\nc\n' > f.txt
_boot 't0'
printf 'A\nb\nc\n' > f.txt
_ci 'b1 edit line 1' f.txt
NLOGS=$(ls "$B"/.be/*.keeper | wc -l)
KBYTES=$(cat "$B"/.be/*.keeper | wc -c)   # JS-117: append = same logs, more bytes

#  TEST-003 rolling-idx quirk: drop stale keeper.idx in BOTH stores pre-op.
rm -f "$S1"/.be/*.keeper.idx "$B"/.be/*.keeper.idx

# BRO-030: golden pins the DERIVED patch col (..vv); WHOLE `?<sha>!` renders ...v
# today — refOf/patchTheirs drops the `!`-suffixed theirs sha (suspected reporter bug).
#  THE LIVE CASE: address the WORKTREE (not its store) across stores.
( cd "$B" && "$JABC" patch "file:$A" ) \
    >"$WORK/js.out" 2>"$WORK/js.err" \
    || _fail "patch failed: $(cat "$WORK/js.err")"

{
    echo "=== stdout ==="; cat "$WORK/js.out"
    echo "=== fetched ==="
    #  JS-117: the fetch tail-APPENDS to the existing sub-threshold log — the
    #  landing proof is byte growth with an UNCHANGED keeper-log count.
    if [ "$(cat "$B"/.be/*.keeper | wc -c)" -gt "$KBYTES" ] \
       && [ "$(ls "$B"/.be/*.keeper | wc -l)" -eq "$NLOGS" ]; then
        echo "objects appended to b's shard log"
    else
        echo "NO tail-append (logs $(ls "$B"/.be/*.keeper | wc -l)/$NLOGS)"
    fi
    echo "=== patch row ==="
    grep -a $'\tpatch\t' "$B/.be/wtlog" | tail -1 | sed -E 's/^[^\t]*\t/T\t/'
    echo "=== status ==="; _jstatus "$B"
    echo "=== file bytes ==="; _fbytes "$B" f.txt
} | golden_assert "$NAME" "$GOLDEN"
pass
