#!/bin/sh
# test/get/line-staged — GET-053 RULING (gritzko 2026-07-29, extended
# 2026-08-01, off the GET-057 incident): the STAGED list survives ANY regular
# get, forward or backward — no silent `...V` -> `...v` demotion; only `get!`
# clears it.
# RED at GET-053 filing: the new get row becomes the put/delete floor
# (wtlog.boundaries().pd), so every earlier put row falls out of scope and the
# staged file reads `...v` right after the get.
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A\n' > a.txt; printf 'S\n' > s.txt
"$BE" post 'c1' >/dev/null 2>&1
C1=$(gr_tip_sha "$SRC")
[ -n "$C1" ] || _fail "no c1 sha"

gr_jclone "$SRC" "$WORK/jT"

# stage a local edit of s.txt — a path the incoming commits never touch.
cd "$WORK/jT"
printf 'S2\n' > s.txt
"$JABC" put s.txt >/dev/null 2>&1 || _fail "put s.txt failed"

st_is_staged() {
    ( cd "$WORK/jT" && "$JABC" status ) > "$WORK/st.out" 2>&1 || true
    grep -qE '\.\.\.V s\.txt' "$WORK/st.out" \
        || { echo "--- status ($1) ---"; cat "$WORK/st.out"; \
             _fail "$1: s.txt is no longer STAGED (\`...V\`)"; }
}
st_is_staged "before the get"

# c2 advances an UNRELATED file — a clean fast-forward for the wt.
cd "$SRC"
printf 'A2\n' > a.txt
"$BE" put a.txt >/dev/null 2>&1
"$BE" post 'c2' >/dev/null 2>&1
C2=$(gr_tip_sha "$SRC")
[ "$C1" != "$C2" ] || _fail "c2 did not advance"

# 1. FAST-FORWARD: theirs lands, ours stays staged.
rc=$(gr_jget "$WORK/jT" "?#$C2")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "ff get exit=$rc"; }
gr_file_is "$WORK/jT/a.txt" "A2"
gr_file_is "$WORK/jT/s.txt" "S2"
st_is_staged "after the fast-forward get"

# 2. FAST-BACKWARD: same rule, the other direction.
rc=$(gr_jget "$WORK/jT" "?#$C1")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "fb get exit=$rc"; }
gr_file_is "$WORK/jT/a.txt" "A"
gr_file_is "$WORK/jT/s.txt" "S2"
st_is_staged "after the fast-backward get"

# 3. `get!` is the SOLE clearing door: the edit is discarded with the staging.
_rc=0
( cd "$WORK/jT" && "$JABC" get! ) >"$WORK/f.out" 2>"$WORK/f.err" || _rc=$?
[ "$_rc" = 0 ] || { cat "$WORK/f.err"; _fail "get! exit=$_rc"; }
gr_file_is "$WORK/jT/s.txt" "S"
( cd "$WORK/jT" && "$JABC" status ) > "$WORK/st.out" 2>&1 || true
if grep -qE ' s\.txt$' "$WORK/st.out"; then
    echo "--- status ---"; cat "$WORK/st.out"
    _fail "get! left s.txt staged/dirty"
fi

pass
