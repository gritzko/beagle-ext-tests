#!/bin/sh
# test/get/divergent-track-update — GET-040 (DIS-082-jab incident 2026-07-31):
# a NON-force bare `jab get` on a wt-URI track must NEVER delete a local-only
# (staged-new/committed-add) file, never resurrect a local delete, and must
# keep ours for a file theirs left untouched — only `get!` cleans.  Two arms:
#   1. FF update over a STAGED set (staged-new + staged delete + dirty put):
#      the merkle prune leaves them alone, theirs' unrelated change lands.
#   2. the incident: the local set is POSTED (base diverges from the track),
#      the track advances on an UNRELATED file, bare get.  Before the fix the
#      diverged UPDATE ran the GET-048 switch-reset: the local add was
#      UNLINKED, the local delete resurrected, ours reverted to theirs.
# An EXPLICIT `get ?branch` switch keeps the GET-048 reset semantics
# (test/get/divergent-clean-reset etc); only the TRACK-UPDATE forms merge.
. "$(dirname "$0")/../../lib/getrepro.sh"

# URI-016: bound the `//X` project-root climb at this case's scratch.
export BE_ROOT="$WORK"

# ONE project store; `//srcwt` IS `<proj>/work/srcwt` (track-wt-bare layout).
PROJ="$WORK/proj"
mkdir -p "$PROJ/.be" "$PROJ/work"
printf 'R\n' > "$PROJ/readme.txt"
( cd "$PROJ" && "$JABC" post 'main tree' ) >/dev/null 2>&1 || _fail "seed PROJ failed"
MAIN=$(gr_tip_sha "$PROJ")
[ -n "$MAIN" ] || _fail "no main tip"

SRCWT="$PROJ/work/srcwt"
mkdir -p "$SRCWT"
( cd "$SRCWT" && "$JABC" get "file:$PROJ/.be#$MAIN" ) >/dev/null 2>&1 \
    || _fail "clone srcwt failed"
printf 'T1\n' > "$SRCWT/t.txt"           # the upstream-advance probe
printf 'K\n'  > "$SRCWT/keep.txt"        # ours will edit; theirs never touches
printf 'D\n'  > "$SRCWT/doomed.txt"      # ours will delete; theirs never touches
( cd "$SRCWT" && "$JABC" put t.txt keep.txt doomed.txt && "$JABC" post 't1' ) \
    >/dev/null 2>&1 || _fail "advance srcwt (t1) failed"
TIP1=$(gr_tip_sha "$SRCWT")

# the tracker: `get //srcwt` clones srcwt's tree, tracking `//srcwt#<tip1>`.
DEST="$PROJ/work/dest"
mkdir -p "$DEST"
( cd "$DEST" && "$JABC" get '//srcwt' ) >"$WORK/g.out" 2>"$WORK/g.err" \
    || { cat "$WORK/g.err"; _fail "get //srcwt failed"; }
gr_file_is "$DEST/doomed.txt" "D"

# ============================================================================
# 1. FF track update over a STAGED set: staged-new + staged delete + dirty put
#    survive; theirs' unrelated t.txt change lands.
# ============================================================================
( cd "$DEST" \
  && printf 'NEW\n'  > snew.txt && "$JABC" put snew.txt \
  && printf 'OURS\n' > keep.txt && "$JABC" put keep.txt \
  && "$JABC" delete doomed.txt ) >/dev/null 2>&1 || _fail "stage set (arm 1) failed"
[ ! -e "$DEST/doomed.txt" ] || _fail "delete doomed.txt left the file on disk"

printf 'T2\n' > "$SRCWT/t.txt"
( cd "$SRCWT" && "$JABC" put t.txt && "$JABC" post 't2' ) >/dev/null 2>&1 \
    || _fail "advance srcwt (t2) failed"
TIP2=$(gr_tip_sha "$SRCWT")
[ -n "$TIP2" ] && [ "$TIP2" != "$TIP1" ] || _fail "srcwt did not advance to t2"

rc=$(gr_jget "$DEST")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "FF bare get exit=$rc"; }
gr_file_is "$DEST/t.txt" "T2"
gr_file_is "$DEST/snew.txt" "NEW"
[ ! -e "$DEST/doomed.txt" ] || _fail "FF get resurrected a staged delete (doomed.txt)"
gr_file_is "$DEST/keep.txt" "OURS"
echo "ok   1. FF: staged-new + staged delete + dirty put survive the bare get"

# ============================================================================
# 2. the DIS-082-jab incident: the set is re-staged and POSTED (the base now
#    DIVERGES from the track), srcwt advances on the unrelated t.txt, bare get.
#    The non-force TRACK UPDATE must merge-or-leave, never switch-reset.
# ============================================================================
( cd "$DEST" \
  && "$JABC" put snew.txt && "$JABC" put keep.txt && "$JABC" delete ) \
    >/dev/null 2>&1 || _fail "re-stage set (arm 2) failed"
( cd "$DEST" && "$JABC" post 'p1' ) >/dev/null 2>&1 || _fail "local post p1 failed"
PTIP=$(gr_tip_sha "$DEST")
[ -n "$PTIP" ] && [ "$PTIP" != "$TIP2" ] || _fail "local post did not move the base"

printf 'T3\n' > "$SRCWT/t.txt"
( cd "$SRCWT" && "$JABC" put t.txt && "$JABC" post 't3' ) >/dev/null 2>&1 \
    || _fail "advance srcwt (t3) failed"
TIP3=$(gr_tip_sha "$SRCWT")
[ -n "$TIP3" ] && [ "$TIP3" != "$TIP2" ] || _fail "srcwt did not advance to t3"

rc=$(gr_jget "$DEST")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "divergent bare get exit=$rc"; }

# theirs' unrelated change still lands, and the track re-points to tip3.
gr_file_is "$DEST/t.txt" "T3"
gr_wtlog_has "$DEST" "//srcwt#$TIP3"
# the GET-040 invariant: local-only content survives a NON-force track update.
[ -f "$DEST/snew.txt" ] \
    || _fail "non-force diverged get DELETED a local-only file (snew.txt) — silent data loss"
gr_file_is "$DEST/snew.txt" "NEW"
[ ! -e "$DEST/doomed.txt" ] \
    || _fail "non-force diverged get RESURRECTED a locally-deleted file (doomed.txt)"
gr_file_is "$DEST/keep.txt" "OURS"
echo "ok   2. DIVERGED track update: local add/delete/edit all survive, theirs lands"

pass
