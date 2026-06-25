#!/bin/sh
# JSQUE-011 parity case: `be delete` via the resident loop — full-line byte
# parity, native `be delete` vs `jab be/loop.js delete` (SUT=loop).  DELETE
# is the per-file UNLINK leaf + the dir-form PREFLIGHT barrier + the `?br`
# branch tombstone; this gates the delete.js -> handler conversion through the
# shared seed+emit loop entry (JSQUE-008).  Covers file / dir / bare-missing /
# branch, modelled on test/js/delete (be-js-delete) + the status parity case.
#
# Forks a committed baseline into a native + JS side (separate stores via
# reanchor), mutates BOTH identically, then asserts native `be delete` and the
# loop's delete are byte-identical on stdout AND on the wtlog `delete` rows,
# the project-shard refs rows, and the on-disk file set (DELETE mutates the wt,
# so the file set is part of the contract — verb_parity does not check it).
# Default $SUT=oneshot gates today's delete.js; `SUT=loop` gates the JSQUE-011
# handler via be/loop.js — same case file, no edit.
. "$(dirname "$0")/../../lib/parity.sh"

# delete_parity ARGS… — run native `be delete ARGS` in $NAT and the JS path
# (per $SUT) in $JS, both in-place, then assert stdout + wtlog `delete` rows +
# refs rows + the on-disk file set.  (verb_parity covers the first three;
# DELETE also mutates files, so the file set is asserted here too.)
_fileset() { ( cd "$1" && find . -type f | grep -vE '/\.be|^\./\.be' | sort ); }
delete_parity() {
    verb_parity delete "$@"
    _fileset "$NAT" >"$WORK/.nfiles"; _fileset "$JS" >"$WORK/.jfiles"
    cmp -s "$WORK/.nfiles" "$WORK/.jfiles" || {
        echo "--- native files ---"; cat "$WORK/.nfiles"
        echo "--- js files ---";     cat "$WORK/.jfiles"
        _fail "on-disk file set differs"; }
}

# 1. file-form: delete one tracked file present on disk (unlink + one row).
seed_baseline 'printf "A\n" > a.txt; printf "B\n" > b.txt'
fork_pair
delete_parity a.txt
echo "ok: file-form delete parity passes"

# 2. dir-form: `<dir>/` recursive unlink + ONE `delete <dir>/` row (the
#    preflight barrier runs before any unlink); files outside untouched.
seed_baseline 'mkdir src; printf "C\n" > src/a.c; printf "D\n" > src/b.c; printf "R\n" > README.md'
fork_pair
delete_parity 'src/'
echo "ok: dir-form delete parity passes"

# 3. bare-missing: bare `be delete` sweeps tracked files gone from disk — one
#    `delete <path>` row per gone file in tree-walk order; on-disk untouched.
seed_baseline 'mkdir src; printf "A\n" > a.txt; printf "Z\n" > z.txt; printf "M\n" > src/m.c; printf "B\n" > src/b.c'
fork_pair
mutate 'rm a.txt z.txt src/m.c src/b.c'
delete_parity
echo "ok: bare-missing sweep parity passes"

# 4. dirty refusal (JSQUE-014): a clean arg (a.txt) is unlinked + row'd, then a
#    user-edited arg (stray.txt, mtime ∉ stamp-set) aborts the batch DELDIRTY.
#    The loop-edge flush must emit the PARTIAL `delete:` banner to stdout (byte
#    -parity) AND both sides must exit NON-ZERO (the unified loop-edge maps the
#    handler throw → flush → process exit; delete.js no longer flushes itself).
seed_baseline 'printf "A\n" > a.txt'
fork_pair
mutate 'sleep 0.02; printf "stray\n" > stray.txt'
( cd "$NAT" && run_native delete a.txt stray.txt ) >"$NAT.out" 2>"$NAT.err" && \
    _fail "native dirty delete did not refuse (zero exit)"
( cd "$JS"  && run_js     delete a.txt stray.txt ) >"$JS.out"  2>"$JS.err"  && \
    _fail "JS dirty delete did not refuse (zero exit)"
assert_stdout "$NAT.out" "$JS.out"
assert_wtlog  "$NAT" "$JS" delete
grep -q DELDIRTY "$JS.err" || _fail "JS dirty delete refused but not via DELDIRTY: $(cat "$JS.err")"
echo "ok: dirty-refusal partial-banner + non-zero exit parity passes"

# 5. branch tombstone: `be delete ?br` drops a leaf branch label via a REFS
#    `delete ?br#0…0` tombstone (no wt change); refs rows must agree.
seed_baseline 'printf "A\n" > a.txt'
fork_pair
mutate '"$BE" put "?feat" >/dev/null 2>&1'
delete_parity '?feat'
echo "ok: branch-tombstone delete parity passes"

pass

