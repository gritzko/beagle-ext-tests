#!/bin/sh
# test/get/track-update-staged — GET-040's surviving arm, rescued from
# test/get/divergent-track-update when GET-053 retired that case (its second
# arm asserted a DIVERGED bare track update must MERGE — the exact behaviour
# the FF/FB line gate refuses; see test/get/line-diverged).
# The subject here is untouched and still law: a NON-force bare `jab get` on a
# wt-URI track that FAST-FORWARDS must never delete a local-only (staged-new)
# file, never resurrect a staged delete, and must keep ours for a file theirs
# left alone — the merkle prune leaves them be, theirs' own change lands.
# Only `get!` cleans (test/sub/untracked, test/get/line-staged).
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

# FF track update over a STAGED set: staged-new + staged delete + dirty put
# survive; theirs' unrelated t.txt change lands.
( cd "$DEST" \
  && printf 'NEW\n'  > snew.txt && "$JABC" put snew.txt \
  && printf 'OURS\n' > keep.txt && "$JABC" put keep.txt \
  && "$JABC" delete doomed.txt ) >/dev/null 2>&1 || _fail "stage set failed"
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
gr_wtlog_has "$DEST" "//srcwt#$TIP2"

pass
