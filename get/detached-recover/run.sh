#!/bin/sh
# test/get/detached-recover — GET-047, THE RULED CORNER (gritzko 2026-07-16):
# in a DETACHED wt (record `#<sha>`, DIS-075) a bare `jab get` targets the BASE
# commit and recovers the full tree — missing files restored, dirty edits woven
# in (GET.mkd 2.1), exit 0, the wt STAYS detached (record shape unchanged).
#
# MISMATCH at tip fe042740 (hence run.sh.broken, not registered): the bare get
# ignores the detached record — inRepoSeed folds curBranch="" into
# resolveRef("") = the TRUNK ref, so with a published trunk the wt JUMPS to the
# trunk tip: z.txt (trunk-only) appears, a.txt weaves into conflict markers,
# exit 1 (GETCONF), and the appended row is trunk-shaped `get?#<trunk tip>` —
# the wt silently RE-ATTACHES.  b.txt (deleted on disk) is not restored either
# (merkle-prune vs the trunk tree skips the unchanged entry).  Observed:
#   rc=1; a.txt="<<<<A2||||MANGLED>>>>"; b.txt missing; z.txt present;
#   wtlog tail: get#<C1> get?#<C2> con a.txt;  refs label flips off ?<C1>.
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC=$(gr_src src)
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"

# a PUBLISHED trunk ref PAST the detach target — the strongest fixture: any
# "resolve the tracked branch" fallback lands c2, only target=BASE lands c1.
cd "$SRC"
printf 'A2\n' > a.txt; printf 'Z\n' > z.txt
"$BE" put a.txt z.txt >/dev/null 2>&1
"$BE" post 'c2' >/dev/null 2>&1
C2=$(gr_tip_sha "$SRC")
[ "$C1" != "$C2" ] || _fail "c2 did not advance"
"$BE" post '?' >/dev/null 2>&1 || _fail "publish trunk@c2 failed"

# clone at c2, then DETACH at c1 (`?<sha>` argument -> `#<sha>` record).
gr_jclone "$SRC" "$WORK/jT"
rc=$(gr_jget "$WORK/jT" "?$C1")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "detach get ?<c1> exit=$rc"; }
gr_wtlog_has "$WORK/jT" "get#$C1"
gr_file_is "$WORK/jT/a.txt" "A"
[ ! -e "$WORK/jT/z.txt" ] || _fail "detach left z.txt (a c2-only file)"

# the damage: a DELETED tracked file + a MANGLED (dirty-edited) one.
rm "$WORK/jT/b.txt"
printf 'MANGLED\n' > "$WORK/jT/a.txt"

# THE RULING: bare `jab get` recovers the full tree AT THE BASE (c1), exit 0.
# GET-047: snapshot the wtlog BEFORE the bare get — the clone row is itself
# `get?#<c2>`, so the no-re-attach probe must scan only the APPENDED tail.
PRE=$(gr_wtraw "$WORK/jT")
rc=$(gr_jget "$WORK/jT")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "detached bare get exit=$rc"; }

# missing file restored byte-exact from the base tree.
gr_file_is "$WORK/jT/b.txt" "B"
# target = BASE, never the trunk tip: no c2-only content may appear.
[ ! -e "$WORK/jT/z.txt" ] || _fail "detached bare get jumped to the TRUNK tip (z.txt appeared)"
# the dirty edit is WOVEN IN (GET.mkd 2.1: base==target keeps the local edit),
# never a conflict, never a clobber.
gr_file_is "$WORK/jT/a.txt" "MANGLED"

# still detached: `jab refs` keeps the detached label `?<c1>` (record shape
# unchanged), and no trunk-shaped `?#` row re-attached the wt behind our back.
LABEL=$( ( cd "$WORK/jT" && "$JABC" refs 2>/dev/null ) | sed -n 's/^branch: *//p' )
[ "$LABEL" = "?$C1" ] \
    || _fail "detached bare get re-attached the wt: refs label [$LABEL] want [?$C1]"
POST=$(gr_wtraw "$WORK/jT")
printf '%s\n' "${POST#"$PRE"}" | grep -qE "get\\?#$C2" \
    && _fail "detached bare get recorded the trunk tip (get?#<c2>)" || true

pass
