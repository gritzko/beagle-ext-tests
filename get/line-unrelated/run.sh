#!/bin/sh
# test/get/line-unrelated — GET-053: an UNRELATED target (disjoint history,
# no common ancestor) is off cur's line too, so a regular `get` refuses it in
# plain words.  This is the "another project in the cell's clothes" hazard
# GET-047 guards for `//X`, now covered for every seed.
# RED at GET-053 filing: the `file:` seed happily anchors the foreign tip —
# the old tree is unreadable in the new store, so nothing is deleted and the
# two projects' files pile up in one wt (rc=0, silent).
. "$(dirname "$0")/../../lib/getrepro.sh"

# Project P: a.txt/b.txt, its own root commit.
SRC=$(gr_src src)
gr_jclone "$SRC" "$WORK/jT"
gr_file_is "$WORK/jT/a.txt" "A"

# Project Q: a SEPARATE store with its OWN root commit — disjoint history.
ORPH="$WORK/orph"; mkdir -p "$ORPH"; cd "$ORPH"; mkdir .be
printf 'O\n' > o.txt
"$BE" post 'oc1' >/dev/null 2>&1
OTIP=$(gr_tip_sha "$ORPH")
[ -n "$OTIP" ] || _fail "no orphan tip"

PRE=$(gr_wtraw "$WORK/jT")

# 1. the REFUSAL.
rc=$(gr_jget "$WORK/jT" "file://$ORPH/.be#$OTIP")
[ "$rc" != 0 ] || { cat "$WORK/last.out"; _fail "unrelated get was ACCEPTED"; }
grep -q 'not on this line' "$WORK/last.err" \
    || { cat "$WORK/last.err"; _fail "refusal does not say 'not on this line'"; }

# 2. nothing moved: no foreign file landed, no wtlog row appended.
[ ! -e "$WORK/jT/o.txt" ] || _fail "refused get still checked out the foreign tree"
gr_file_is "$WORK/jT/a.txt" "A"
[ "$(gr_wtraw "$WORK/jT")" = "$PRE" ] \
    || { echo "--- wtlog grew ---"; gr_wtraw "$WORK/jT"; echo; \
         _fail "refused get still appended a wtlog row"; }

# 3. `get!` reaches any commit — including unrelated history (/wiki/GET
#    "not necessarily fast-forward or fast-backward").
_rc=0
( cd "$WORK/jT" && "$JABC" get! "file://$ORPH/.be#$OTIP" ) \
    >"$WORK/f.out" 2>"$WORK/f.err" || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/f.err"; _fail "get! onto unrelated exit=$_rc"; }
gr_file_is "$WORK/jT/o.txt" "O"

pass
