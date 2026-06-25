#!/bin/sh
# JSQUE-013 parity case: `be patch` via the resident loop — full-line byte
# parity, native `be patch` vs `jab be/loop.js patch` (SUT=loop).  PATCH is the
# per-file 3-way WEAVE-merge LEAF (the JS-052 full-history weave engine) folded
# under the single-provenance `patch` BARRIER row (ONE row for the whole
# absorbed set, NOT per-file).  This gates the patch.js -> handler conversion
# through the shared seed+emit loop entry (JSQUE-008); the (ours,theirs,fork)
# triple is pinned at seed (resolve.seed).  Covers a clean cherry weave + a
# multi-file absorb, modelled on the status parity case + be-js-patch (JS-052).
#
# Forks a committed baseline into a native + JS side (separate stores via
# reanchor), builds a trunk/feat divergence IDENTICALLY in both (mutate), then
# asserts native `be patch <uri>` and the loop's patch are byte-identical on
# stdout AND on the wtlog `patch` row (the single-provenance barrier) AND on the
# merged on-disk file set.  SOURCE_DATE_EPOCH pins the commit shas so the patch
# row uri (theirs sha) + the conflict-fence side order are stable (JS-052).
# Default $SUT=oneshot gates today's patch.js; `SUT=loop` gates the JSQUE-013
# handler via be/loop.js — same case file, no edit.
. "$(dirname "$0")/../../lib/parity.sh"

#  JSQUE-013/JS-052: pin the reproducible-build clock so both forks' `be post`
#  shas (and thus the `patch ?<sha>` row uri) coincide run-to-run.
: "${SOURCE_DATE_EPOCH:=1467331200}"; export SOURCE_DATE_EPOCH   # 2016-07-01Z
: "${TZ:=UTC}"; export TZ

# Native `be patch` frames its output with a `post ?<sha>#<subj>` commit-style
# header + a `noop=… take-theirs=…` stats summary; the JS port (JS-052 contract)
# emits a `patch:` header instead.  Both are cosmetic native-only framing — the
# byte-parity contract is the PER-FILE STATUS ROWS (applied/merged/conf/del/…),
# so normalise to those (date-folded), exactly as patchcase.sh's _normbanner.
_normbanner() {
    sed -E 's/^ *[0-9]{1,2}:[0-9]{2} */T /' \
      | awk '$2=="applied"||$2=="merged"||$2=="conf"||$2=="del"||$2=="modl"||$2=="failed"||$2=="add"' \
      || true
}
assert_banner() {
    _normbanner <"$1" >"$1.ban"; _normbanner <"$2" >"$2.ban"
    cmp -s "$1.ban" "$2.ban" || {
        echo "--- native stdout ($1) ---"; cat "$1"
        echo "--- js stdout ($2) ---";     cat "$2"
        echo "--- diff (status rows) ---"; diff "$1.ban" "$2.ban" || true
        _fail "patch status rows differ"; }
}

# patch_parity URI FILES… — run native `be patch URI` in $NAT and the JS path
# (per $SUT) in $JS, both in-place, then assert the per-file status rows match +
# the wtlog `patch` row (the single-provenance barrier) + the merged on-disk
# bytes.  The wtlog `patch` row is the load-bearing byte-parity proof: exactly
# ONE row carrying theirs' sha + scope slot, for the WHOLE absorbed file set.
patch_parity() {
    _pp_uri=$1; shift
    ( cd "$NAT" && run_native patch "$_pp_uri" ) >"$NAT.out" 2>"$NAT.err" || true
    ( cd "$JS"  && run_js     patch "$_pp_uri" ) >"$JS.out"  2>"$JS.err"  || true
    assert_banner "$NAT.out" "$JS.out"
    assert_wtlog  "$NAT" "$JS" patch
    for _f in "$@"; do
        if [ -e "$NAT/$_f" ] || [ -e "$JS/$_f" ]; then
            cmp -s "$NAT/$_f" "$JS/$_f" || {
                echo "--- native $_f ---"; cat "$NAT/$_f" 2>/dev/null
                echo "--- js $_f ---";     cat "$JS/$_f"  2>/dev/null
                _fail "merged wt bytes differ for $_f"; }
        fi
    done
}

# 1. clean cherry weave: trunk T1 edits line 1, feat F1 edits line 3 (disjoint).
#    `patch #<F1>` is a clean 3-way merge — f.txt carries BOTH edits, no markers,
#    ONE `patch #<sha>` provenance row.  (Single file, single absorbed commit.)
seed_baseline 'printf "a\nb\nc\nd\ne\n" > f.txt'
fork_pair
mutate '"$BE" put "?./feat" >/dev/null 2>&1
        "$BE" get "?.." >/dev/null 2>&1
        printf "A\nb\nc\nd\ne\n" > f.txt
        "$BE" put f.txt >/dev/null 2>&1; "$BE" post "t1" >/dev/null 2>&1
        "$BE" get "?feat" >/dev/null 2>&1
        printf "a\nb\nC\nd\ne\n" > f.txt
        "$BE" put f.txt >/dev/null 2>&1; "$BE" post "f1" >/dev/null 2>&1
        "$BE" get "?.." >/dev/null 2>&1'
#  cur (trunk@T1) carries the same sha in both forks (pinned clock), so a single
#  shared `?feat` NEXT absorb fans the same multi-arg-free single-file leaf.
patch_parity '?feat' f.txt
echo "ok: clean-weave NEXT patch parity passes (single provenance row)"

# 2. multi-file absorb: feat changes TWO files (disjoint from trunk's third),
#    `?feat!` WHOLE-absorbs both into one `patch ?<sha>!` row — the barrier
#    folds BOTH file leaves into ONE provenance row (no fan-out into 2 rows).
seed_baseline 'printf "a\nb\nc\n" > x.txt; printf "p\nq\nr\n" > y.txt; printf "u\nv\nw\n" > z.txt'
fork_pair
mutate '"$BE" put "?./feat" >/dev/null 2>&1
        "$BE" get "?.." >/dev/null 2>&1
        printf "A\nb\nc\n" > x.txt
        "$BE" put x.txt >/dev/null 2>&1; "$BE" post "t1 x" >/dev/null 2>&1
        "$BE" get "?feat" >/dev/null 2>&1
        printf "p\nq\nR\n" > y.txt
        "$BE" put y.txt >/dev/null 2>&1; "$BE" post "f1 y" >/dev/null 2>&1
        printf "u\nV\nw\n" > z.txt
        "$BE" put z.txt >/dev/null 2>&1; "$BE" post "f2 z" >/dev/null 2>&1
        "$BE" get "?.." >/dev/null 2>&1'
patch_parity '?feat!' x.txt y.txt z.txt
echo "ok: multi-file WHOLE absorb parity passes (one barrier row, not fan-out)"

pass
