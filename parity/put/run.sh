#!/bin/sh
# JSQUE-010 parity case: `be put` via the resident loop — full-line byte
# parity, native `be put` vs `jab be/loop.js put` (SUT=loop).  Converts the
# per-verb wave's PUT: each path arg is one seed row → the per-file STAGE LEAF
# (hash, append the `put` row, restamp to the cohort ts); ref-write forms are
# pinned at the seed (core/resolve.js) and applied once from ctx.refs.  Covers
# the LEAF forms JSQUE-010 owns — file / multi-path / dir / move / ref — but
# NOT the bare-walk + move auto-pair BARRIER (DEFERRED).  Each leg builds one
# committed baseline, forks a native + JS side (separate stores via reanchor),
# mutates BOTH identically, then verb_parity asserts the `put:` banner + the
# wtlog `put` rows + the project-shard refs rows are byte-identical (date
# column normalised only).  Default $SUT=oneshot gates today's put.js; flip
# `SUT=loop` to gate the JSQUE-010 handler — same case file, no edit.
. "$(dirname "$0")/../../lib/parity.sh"

# 1. FILE form (single tracked-dirty file) — the per-file STAGE leaf.
seed_baseline 'printf "A\n" > a.txt; printf "B\n" > b.txt'
fork_pair
mutate 'sleep 0.02; printf "A2\n" > a.txt'
verb_parity put a.txt
echo "ok: single-file put parity passes"

# 2. MULTI-PATH form (`put a b c`) — the multi-row seed fan-out (one leaf each:
#    a tracked mod, an untracked add, a nested mod), all file-form (arg order).
seed_baseline 'printf "A\n" > a.txt; printf "B\n" > b.txt; mkdir d; printf "C\n" > d/c.txt'
fork_pair
mutate 'sleep 0.02; printf "A2\n" > a.txt; printf "N\n" > n.txt; printf "C2\n" > d/c.txt'
verb_parity put a.txt n.txt d/c.txt
echo "ok: multi-path put parity passes"

# 3. DIR form (`put <dir>/`) — one seed row that expands to a `put` row per
#    tracked-dirty / untracked file under the prefix, in lex order.
seed_baseline 'mkdir d; printf "C\n" > d/c.txt; printf "E\n" > d/e.txt'
fork_pair
mutate 'sleep 0.02; printf "C2\n" > d/c.txt; printf "F\n" > d/f.txt'
verb_parity put d/
echo "ok: dir-form put parity passes"

# 4. MOVE form (`put <old>#<new>`) — explicit rename leaf: src on disk, dst
#    free → rename on disk + one `put <old>#<new>` row (fragment = dest path).
seed_baseline 'printf "A\n" > a.txt; printf "B\n" > b.txt'
fork_pair
mutate 'sleep 0.02'
verb_parity put 'b.txt#moved.txt'
echo "ok: move-form put parity passes"

# 5. REF-CREATE form (`put ?<branch>`) — branch label at cur.tip; a pure REFS
#    op pinned at the seed (no stdout banner, one refs row).
seed_baseline 'printf "A\n" > a.txt'
fork_pair
verb_parity put '?feat'
echo "ok: ref-create put parity passes"

# 6. REF-SET form (`put ?<branch>#<sha>`) — set ?feat OUTRIGHT to the parent
#    commit (non-FF), pinned at the seed.  Two commits give a parent sha.
seed_baseline 'printf "A\n" > a.txt'
( cd "$BASE" && sleep 0.02 && printf "A2\n" > a.txt && \
  "$BE" put a.txt >/dev/null 2>&1 && "$BE" post c2 >/dev/null 2>&1 )
PAR=$("$JABC" "$_CASE/../../put/parentsha.js" "$BASE")
[ -n "$PAR" ] || _fail "could not resolve parent sha"
fork_pair
verb_parity put "?feat#$PAR"
echo "ok: ref-set put parity passes"

# 7. PUTNONE refusal (JSQUE-014): an all-skip named put (a path that does not
#    exist) stages NOTHING — native emits the `put:` banner + the skip line then
#    returns PUTNONE.  The loop edge must flush that PARTIAL banner to stdout
#    (byte-parity) AND exit NON-ZERO (put.js's PUTNONE was previously UNWIRED —
#    it exited 0; the unified loop-edge now maps the throw → flush → exit).
seed_baseline 'printf "A\n" > a.txt'
fork_pair
( cd "$NAT" && run_native put nope.txt ) >"$NAT.out" 2>"$NAT.err" && \
    _fail "native all-skip put did not refuse (zero exit)"
( cd "$JS"  && run_js     put nope.txt ) >"$JS.out"  2>"$JS.err"  && \
    _fail "JS all-skip put did not refuse (zero exit)"
assert_stdout "$NAT.out" "$JS.out"
grep -q PUTNONE "$JS.err" || _fail "JS all-skip put refused but not via PUTNONE: $(cat "$JS.err")"
echo "ok: all-skip PUTNONE partial-banner + non-zero exit parity passes"

pass
