#!/bin/sh
# test/get/track-wt-bare — GET-047 / GET.mkd 1.1 + 1.3: a bare `jab get` in a
# wt whose recentmost record tracks a WORKTREE (`//X#<sha>`, the wt-operand
# clone shape) re-resolves that track — reads //X's CURRENT base and takes it
# (HISTORY: AHEAD x an already-tracked //wt).
#
# MISMATCH at tip fe042740 (hence run.sh.broken, not registered): inRepoSeed
# never re-reads the `//X` track — curTip() drops the authority row's branch
# (non-local), the bare get folds to resolveRef("")-else-curSha, exits 0 as a
# same-tip no-op AND appends a trunk-pin `get?#<old sha>` row that REPLACES the
# `//srcwt` track (the recentmost record no longer names the worktree).
# Observed after advancing srcwt (new t2.txt, tip d4108bb8...):
#   rc=0; t2.txt absent in the tracker; wtlog tail: get//srcwt#<old> get?#<old>.
. "$(dirname "$0")/../../lib/getrepro.sh"

# URI-016: bound the `//X` project-root climb at this case's scratch (ctest's
# own $BE_ROOT sits higher and sees unrelated anchors) — the wt-operand pattern.
export BE_ROOT="$WORK"

# ONE project store; worktrees clone it (never bootstrap their own): `//srcwt`
# IS `<proj>/work/srcwt` ([/wiki/URI] step 2, rs_work_root layout).
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
printf 'T1\n' > "$SRCWT/t.txt"
( cd "$SRCWT" && "$JABC" put t.txt && "$JABC" post 't1' ) >/dev/null 2>&1 \
    || _fail "advance srcwt (t1) failed"
TIP1=$(gr_tip_sha "$SRCWT")

# the tracker: `get //srcwt` clones srcwt's tree into DEST, tracking
# `//srcwt#<tip1>` (the DIS-062/063 wt-operand shape).
DEST="$PROJ/work/dest"
mkdir -p "$DEST"
( cd "$DEST" && "$JABC" get '//srcwt' ) >"$WORK/g.out" 2>"$WORK/g.err" \
    || { cat "$WORK/g.err"; _fail "get //srcwt failed"; }
gr_file_is "$DEST/t.txt" "T1"
gr_wtlog_has "$DEST" "//srcwt#$TIP1"

# advance the SOURCE wt past the tracked rev.
printf 'T2\n' > "$SRCWT/t2.txt"
( cd "$SRCWT" && "$JABC" put t2.txt && "$JABC" post 't2' ) >/dev/null 2>&1 \
    || _fail "advance srcwt (t2) failed"
TIP2=$(gr_tip_sha "$SRCWT")
[ -n "$TIP2" ] && [ "$TIP2" != "$TIP1" ] || _fail "srcwt did not advance"

# the assertion: a BARE get in the tracker re-resolves `//srcwt` and takes the
# new rev — t2.txt lands, and the appended record keeps the //srcwt track.
rc=$(gr_jget "$DEST")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "bare get in tracker exit=$rc"; }
gr_file_is "$DEST/t2.txt" "T2"
gr_wtlog_has "$DEST" "//srcwt#$TIP2"
# and never a track-dropping trunk-pin row in its place.
gr_wtraw "$DEST" | grep -qE "get\\?#$TIP1" \
    && _fail "bare get replaced the //srcwt track with a trunk-pin ?#<old>" || true

pass
