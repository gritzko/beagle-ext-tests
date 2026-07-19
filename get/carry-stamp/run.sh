#!/bin/sh
# test/get/carry-stamp — GET-050: a bare/advancing get that CARRIES a `put`-
# staged edit (GET-048 §4) must leave the carried file reading DIRTY, even when
# get never rewrote it (the file is merkle-PRUNED: unchanged between the old and
# the new base).  Incident (work/STATUS-016): the put row's BE-011 restamp stays
# in the wtlog stamp-set, so after the base advances the STATUS-011 has(mtime)
# fast path reads the file CLEAN vs the NEW base — status + bare `diff` HIDE the
# dirt while a targeted `diff <file>` shows it, and a post would silently drop it.
# RULING 2026-07-19: get restamps carried/woven outputs into the DIS-057 band
# under its row ceiling (mrg = ceil-1ms → `...v`); classify buckets by offset.
# RED before the fix: post-get `status` + bare `diff` are EMPTY for f.txt.
. "$(dirname "$0")/../../lib/getrepro.sh"

_srctip() { ( cd "$SRC" && "$JABC" refs 2>/dev/null ) | sed -n 's/^cur: *//p'; }

# Source: f.txt (the carried probe, NEVER touched after c1 → prunes on get) and
# g.txt (the mover: c1->c2 advances so the target is genuinely ahead).
SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'FFF\n' > f.txt
printf 'G1\n' > g.txt
"$BE" post 'c1' >/dev/null 2>&1
C1=$(_srctip)
# c2: change g.txt ONLY — f.txt's blob is identical in c1 and c2 (merkle-prune).
printf 'G2\n' > g.txt
"$BE" put g.txt >/dev/null 2>&1
"$BE" post 'c2' >/dev/null 2>&1
C2=$(_srctip)
[ -n "$C1" ] && [ -n "$C2" ] && [ "$C1" != "$C2" ] || _fail "two-commit setup"

# Clone at c1, then STAGE an edit to f.txt (`put` → BE-011 restamp on f.txt).
gr_jclone "$SRC" "$WORK/wt"
gr_jget "$WORK/wt" "?#$C1" >/dev/null 2>&1
gr_file_is "$WORK/wt/f.txt" "FFF"
printf 'FFF-EDIT\n' > "$WORK/wt/f.txt"
( cd "$WORK/wt" && "$JABC" put f.txt ) >/dev/null 2>&1 || _fail "put f.txt"

# The advancing get: base c1->c2 (g.txt moves, f.txt prunes; the put row falls
# below the new get floor).  f.txt on disk stays FFF-EDIT (get never rewrites it).
rc=$(gr_jget "$WORK/wt" "?#$C2")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "advancing get exit=$rc"; }
gr_file_is "$WORK/wt/f.txt" "FFF-EDIT"

# 1. status: the carried f.txt reads the wt-advanced quad `...v` (real dirt vs
#    the new base) — RED today (empty: the stale put stamp false-cleans it).
( cd "$WORK/wt" && "$JABC" status ) > "$WORK/st.out" 2>&1 || true
grep -qE '\.\.\.v f\.txt' "$WORK/st.out" || { echo "--- status ---"; \
    cat "$WORK/st.out"; _fail "carried f.txt not dirty after get (hidden by stale put stamp)"; }

# 2. bare diff LISTS f.txt (the classifier must bucket it, not skip it clean).
( cd "$WORK/wt" && "$JABC" diff ) > "$WORK/df.out" 2>&1 || true
grep -qE '^\+FFF-EDIT$' "$WORK/df.out" || { echo "--- diff ---"; \
    cat "$WORK/df.out"; _fail "bare diff hides the carried f.txt edit"; }

# 3. g.txt (a genuine clean-overwrite to the new base) stays clean — no row: the
#    GET-049 ceiling stamp reads `ok`, the band restamp is carried-files-only.
if grep -qE ' g\.txt$' "$WORK/st.out"; then
    echo "--- status ---"; cat "$WORK/st.out"
    _fail "clean-overwritten g.txt wrongly lit (GET-049 ceiling stamp broken)"
fi

pass
