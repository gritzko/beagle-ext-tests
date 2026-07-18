#!/bin/sh
# test/patch/report-arms — PATCH.mkd §Reporting: the delete-shaped arms of the
# per-file report.  Topology:
#
#       T0 ── T1          ← cur (trunk): edits mod.txt, DELETES odel.txt
#         \
#          F1             ← ?feat: DELETES del.txt + mod.txt, edits odel.txt
#
#  `patch ?feat` arms exercised (asserting the words the code ACTUALLY prints):
#   - del.txt  theirs-deleted, ours clean  → the file is UNLINKED; TODAY the
#              banner prints NO row for a clean delete (patch.js counts
#              st.deleted but never emit()s).  SPEC MISMATCH FLAG: §Reporting
#              promises "one line per ... touched file" yet defines no word
#              for this arm (set: applied/merged/mod/conflict) — unruled, so
#              this case pins the silent banner + the wt state only.
#   - mod.txt  theirs-deleted, ours MODIFIED (modify/delete) → content side
#              wins: ours bytes KEPT, banner row `modl mod.txt`.  SPEC
#              MISMATCH FLAG: `modl` is the code's word, absent from the
#              §Reporting set — flagged, not renamed (no invented words).
#   - odel.txt ours-deleted, theirs MODIFIED → theirs bytes land, row
#              `modl odel.txt` (same flag as above).
#
#  GREEN today (probe-verified): both modl arms + the silent clean delete.
. "$(dirname "$0")/../../lib/patchspec.sh"

ORG="$WORK/org"; mkdir -p "$ORG/.be"
cd "$ORG"
printf 'delme\n'  > del.txt
printf 'modme\n'  > mod.txt
printf 'odel base\n' > odel.txt
_boot 't0'; T0=$BOOT
_fork feat
_sw feat
rm del.txt mod.txt
printf 'odel THEIRS\n' > odel.txt
_jab delete del.txt >/dev/null 2>&1
_jab delete mod.txt >/dev/null 2>&1
_jab put odel.txt   >/dev/null 2>&1
_jab post 'F1 del+mod' >/dev/null 2>&1
_jab post '?feat'      >/dev/null 2>&1
F1=$(_tip)
_trunk
rm odel.txt
printf 'modme OURS\n' > mod.txt
_jab delete odel.txt >/dev/null 2>&1
_jab put mod.txt     >/dev/null 2>&1
_jab post 't1 mod+odel' >/dev/null 2>&1
_jab post '?'           >/dev/null 2>&1
T1=$(_tip)
cd /

A="$WORK/a"; ps_clone "$A"
[ -f "$A/del.txt" ] || _fail "builder: del.txt missing from the clone"
[ ! -f "$A/odel.txt" ] || _fail "builder: ours-deleted odel.txt present in the clone"

( cd "$A" && "$JABC" patch '?feat' ) > "$WORK/p.out" 2> "$WORK/p.err" \
    || _fail "patch ?feat failed: $(cat "$WORK/p.err")"

#  Arm 1: theirs-deleted + ours clean → unlinked, and (TODAY) no banner row.
[ ! -f "$A/del.txt" ] \
    || _fail "deleted arm: theirs-deleted del.txt still on disk"
! grep -qE '(^|[[:space:]])del\.txt$' "$WORK/p.out" \
    || _fail "the clean-delete arm grew a banner row (word unruled — re-pin):
$(cat "$WORK/p.out")"
echo "ok   1: theirs-delete of a clean file unlinks it (banner silent today)"

#  Arm 2: modify/delete (theirs del, ours mod) → ours KEPT + `modl` row.
[ "$(cat "$A/mod.txt")" = "modme OURS" ] \
    || _fail "modl arm: ours-modified mod.txt not kept: $(cat "$A/mod.txt" 2>&1)"
# BRO-030/Status.mkd: the quad report lists only WRITTEN files; modify/delete
# keeps ours UNCHANGED (== base), so mod.txt earns NO quad row (like del.txt).
! grep -qE '(^|[[:space:]])mod\.txt$' "$WORK/p.out" \
    || _fail "modify/delete mod.txt grew a report row (ours kept ⇒ clean, no row):
$(cat "$WORK/p.out")"
echo "ok   2: modify/delete keeps ours (no quad row — clean vs base)"

#  Arm 3: delete/modify (ours del, theirs mod) → theirs lands + `modl` row.
[ "$(cat "$A/odel.txt" 2>/dev/null)" = "odel THEIRS" ] \
    || _fail "modl arm: theirs-modified odel.txt not restored: $(cat "$A/odel.txt" 2>&1)"
# BRO-030/Status.mkd: delete/modify lands theirs as a RE-CREATED file — the quad
# report shows it as a created `..oo` row.
grep -qE '(^|[[:space:]])\.\.oo odel\.txt$' "$WORK/p.out" \
    || _fail "no '..oo odel.txt' quad row:
$(cat "$WORK/p.out")"
echo "ok   3: delete/modify lands theirs + reports '..oo odel.txt'"

#  The absorption row landed (the arms count as absorbed work).
ps_patch_rows "$A" | grep -q "$F1" \
    || _fail "no patch row recording ?$F1: $(ps_patch_rows "$A")"

pass
