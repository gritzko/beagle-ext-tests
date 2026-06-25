#!/bin/sh
# JSQUE-008 parity case: `be status` via the resident loop — full-line byte
# parity, native `be status` vs `jab be/loop.js status` (SUT=loop).  This is
# the pilot verb that gates the seed+emit INTEGRATION seam: argv -> resolve.seed
# -> loop.run({out:emit.create()}) -> the status handler pushes rows via ctx.out
# -> ONE flush.  Read-only (no store write, no barrier), so it runs in-place in
# each fork rather than the clone/verb_parity shape.
#
# Builds one committed baseline, forks a native + JS side (separate stores via
# reanchor), mutates BOTH identically (mod a tracked file + add an untracked
# one + a nested mod), then asserts native `be status` and the loop's status are
# byte-identical (date column normalised only).  A second leg commits the change
# and re-runs on a CLEAN-ish tree (one residual untracked) to cover the ok-heavy
# summary path.  Default $SUT=oneshot gates today's status.js; `SUT=loop` gates
# the JSQUE-008 integrated entry — same case file, no edit.
. "$(dirname "$0")/../../lib/parity.sh"

# status_parity ARGS… — run native `be status ARGS` in $NAT and the JS path
# (per $SUT) in $JS, both in-place, then assert full-line stdout byte-parity.
status_parity() {
    ( cd "$NAT" && run_native status "$@" ) >"$NAT.out" 2>"$NAT.err" || true
    ( cd "$JS"  && run_js     status "$@" ) >"$JS.out"  2>"$JS.err"  || true
    assert_stdout "$NAT.out" "$JS.out"
}

seed_baseline 'printf "A\n" > a.txt; printf "B\n" > b.txt; mkdir d; printf "C\n" > d/c.txt'
fork_pair

# 1. dirty tree: a tracked mod (a.txt), a nested tracked mod (d/c.txt), and an
#    untracked add (n.txt) — exercises mod + unk buckets + the ok count.
mutate 'sleep 0.02; printf "A2\n" > a.txt; printf "N\n" > n.txt; printf "C2\n" > d/c.txt'
status_parity
echo "ok: dirty-tree status parity passes"

# 2. commit the staged change in BOTH forks, then re-run: the tracked files are
#    now ok (count only), one residual untracked remains — the ok-heavy summary.
mutate 'be put a.txt d/c.txt >/dev/null 2>&1; be post m >/dev/null 2>&1'
status_parity
echo "ok: post-commit status parity passes"

pass
