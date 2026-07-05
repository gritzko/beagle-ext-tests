#!/bin/sh
# test/js/ls/listing — JAB-018/JAB-019 parity for the `ls:` / `lsr:`
# worktree-listing VIEWs over the resident loop (`jab loop.js <ls|lsr> <uri>`;
# the scheme is the verb).  Pure JS over classify+emit; the handler spawns NO
# dog binary and reads NO /proc.
#
# CONTRACT (one hunk == one directory, gritzko 2026-06-24):
#  * `ls:<dir>`  is ONE hunk — that directory's immediate entries (files as
#    status rows, subdirs/mounts as `dir` rows) — BYTE-IDENTICAL to native
#    `be ls:<dir> --plain` (native ls: is itself one-level / one-hunk).  Driven
#    by the differential `ls_eq` harness.
#  * `lsr:` is the WORK-QUEUE / per-directory design: the same per-dir hunk,
#    then one enqueued `lsr:<subdir>` child row per subdir + mounted submodule,
#    so the queue drives the recursion — one hunk per directory, BFS order,
#    blank-line separated.  Each hunk equals native `ls:<thatdir>`, so
#    `lsr_hunks` validates every hunk against native `ls:` and pins the BFS
#    coverage + order.  (NOT native lsr:'s monolithic depth-indented hunk.)
#
# One seeded worktree exercises every bucket + both verbs:
#   eq (clean tracked), dir-collapse (one-level subdir row), mod (edited),
#   unk (untracked), mov (`-> dst` arrow) + its new dst, mis (rm w/o delete);
#   lsr: per-dir hunks via the queue; ls:sub/ + ls:deep/ prefix scope;
#   ls:nope/ empty scope (banner + 0 rows).
. "$(dirname "$0")/../lib/lscase.sh"

WT=$(new_wt listing)
cd "$WT"
mkdir -p sub deep/inner
printf 'A\n'  > a.txt
printf 'B\n'  > b.txt
printf 'G\n'  > gone.txt
printf 'S1\n' > sub/s1.txt
printf 'S2\n' > sub/s2.txt
printf 'D\n'  > deep/d.txt
printf 'I\n'  > deep/inner/i.txt
"$BE" post -m base >/dev/null 2>&1 || "$BE" post base >/dev/null 2>&1

# --- 1. clean tree: eq rows + one-level dir collapse -----------------------
ls_rel   "clean ls: (eq + dir collapse)"   'ls:'
# lsr: BFS = root, deep/, sub/, deep/inner/ (root enqueues deep/,sub/ lex;
# deep/ enqueues deep/inner/) — each hunk == native ls: of that dir (relative).
lsr_rel  "clean lsr: (per-dir hunks, BFS)" 'lsr:' -- '' 'deep/' 'sub/' 'deep/inner/'

# --- 2. dirty tree: mod + unk + RENAME-pair + mis -------------------------
# DIS-057 RULING 2026-06-29: a staged rename now lists as the `rmv`(src)+`mov`
# (dst) move PAIR (status's form), UNTIED from native ls:'s `mov src -> dst` +
# `new dst`.  So the dirty hunks are asserted JS-only (date-normalised golden),
# NOT against native (the rename form diverges); the rest of the listing
# (mod/unk/mis/dir-collapse) is unchanged and rides the same golden.
sleep 0.02
printf 'A2\n' >> a.txt          # mod a.txt
printf 'NEW\n' > new.txt        # unk new.txt
rm gone.txt                     # mis gone.txt (rm without be delete)
"$BE" put b.txt#c.txt >/dev/null 2>&1   # rename b.txt -> c.txt → rmv b + mov c
ls_js  "dirty ls: (mod/unk/RENAME-pair/mis)" 'ls:' 'ls
 DATE  mod a.txt
 DATE  rmv b.txt
 DATE  mov c.txt
        dir deep/
        mis gone.txt
 DATE  unk new.txt
        dir sub/'
# lsr: only the ROOT hunk diverges (the rename pair); the subdir hunks still
# equal native ls: of that dir (all `eq`), so mix the JS root golden with native.
lsr_mixed "dirty lsr: (mod/unk/RENAME-pair/mis)" 'lsr:' 'lsr
 DATE  mod a.txt
 DATE  rmv b.txt
 DATE  mov c.txt
        dir deep/
        mis gone.txt
 DATE  unk new.txt
        dir sub/' -- 'deep/' 'sub/' 'deep/inner/'

# --- 3. prefix scope: subdir + deep nesting + empty scope -----------------
ls_rel    "scope ls:sub/"                   'ls:sub/'
lsr_rel   "scope lsr:sub/"                  'lsr:sub/'        -- 'sub/'
ls_rel    "scope ls:deep/ (nested collapse)" 'ls:deep/'
lsr_rel   "scope lsr:deep/ (nested recurse)" 'lsr:deep/'      -- 'deep/' 'deep/inner/'
ls_rel    "scope ls:deep/inner/"            'ls:deep/inner/'
lsr_rel   "scope lsr:deep/inner/"           'lsr:deep/inner/' -- 'deep/inner/'
ls_rel    "empty scope ls:nope/"            'ls:nope/'
lsr_rel   "empty scope lsr:nope/"           'lsr:nope/'       -- 'nope/'

pass
