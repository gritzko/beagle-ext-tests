#!/bin/sh
# test/get/fragment-sha — GET-047 / GET.mkd 1.4: the pure-fragment spelling
# `get '#<sha>'` (full sha or a hashlet prefix) is a direct commit checkout
# that DETACHES the wt — exactly like the tested `?<sha>` argument: the record
# is the detached `#<sha>` shape (query slot ABSENT, DIS-075), never `?#<sha>`.
#
# MISMATCH at tip fe042740 (hence run.sh.broken, not registered): inRepoSeed
# routes a bare `#<hex>` through the D1 PIN arm (frag set, query folded ""),
# so the record comes out TRUNK-shaped `get?#<sha>` — the wt stays ATTACHED
# (refs label `?`, post would advance the trunk), the checkout itself lands
# the right tree.  Observed after `get '#<c1>'` from a clone at c2:
#   rc=0; a.txt=A (tree ok); wtlog tail: get?#<C1>; refs label `?` not `?<C1>`.
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC=$(gr_src src)
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"

# a second commit so the fragment checkout observably MOVES the wt.
cd "$SRC"
printf 'A2\n' > a.txt; printf 'Z\n' > z.txt
"$BE" put a.txt z.txt >/dev/null 2>&1
"$BE" post 'c2' >/dev/null 2>&1
C2=$(gr_tip_sha "$SRC")
[ "$C1" != "$C2" ] || _fail "c2 did not advance"

gr_jclone "$SRC" "$WORK/jT"
gr_file_is "$WORK/jT/a.txt" "A2"

# --- 1. full-sha fragment: `get '#<c1>'` detaches at c1 ---------------------
rc=$(gr_jget "$WORK/jT" "#$C1")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get '#<c1>' exit=$rc"; }
gr_file_is "$WORK/jT/a.txt" "A"
[ ! -e "$WORK/jT/z.txt" ] || _fail "'#<c1>' checkout left z.txt (a c2-only file)"
# the DETACHED record `#<sha>` (DIS-075), never the attached trunk-pin `?#<sha>`.
gr_wtlog_has "$WORK/jT" "get#$C1"
gr_wtraw "$WORK/jT" | grep -qE "get\\?#$C1" \
    && _fail "get '#<sha>' recorded the ATTACHED trunk-pin ?#<sha>, not the detached #<sha>" || true
# `jab refs` agrees: the detached label `?<c1>`, not the trunk `?`.
LABEL=$( ( cd "$WORK/jT" && "$JABC" refs 2>/dev/null ) | sed -n 's/^branch: *//p' )
[ "$LABEL" = "?$C1" ] \
    || _fail "refs label after get '#<sha>': got [$LABEL] want [?$C1] (detached)"

# --- 2. hashlet prefix: `get '#<10hex>'` resolves + detaches the same -------
rc=$(gr_jget "$WORK/jT" "?#$C2")           # re-attach at c2 first
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "re-pin ?#<c2> exit=$rc"; }
SHORT=$(printf '%s' "$C1" | cut -c1-10)
rc=$(gr_jget "$WORK/jT" "#$SHORT")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "get '#<hashlet>' exit=$rc"; }
gr_file_is "$WORK/jT/a.txt" "A"
gr_wtlog_has "$WORK/jT" "get#$C1"

pass
