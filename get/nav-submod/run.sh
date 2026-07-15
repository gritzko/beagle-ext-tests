#!/bin/sh
# BE-030 test/get/nav-submod — a bare `:get` under a `//parent` nav context, run
# while cwd is a SUBMODULE (a nested worktree whose `.be` is a FILE redirect),
# must REFRESH THE CONTEXT TREE (inRepoSeed on be.repo=parent), NEVER clone the
# parent INTO the sub's cwd.  The bug: get anchored its write/clone on raw
# io.cwd(), so `:get //parent` appended the parent's `?branch#tip` row to the
# SUB's `.be` wtlog and checked the parent out over it.  RED-first repro; SUT=loop
# (jab main.js); JS-ONLY, NO wire/keeper (a local `file:` secondary clone).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/get/nav-submod
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "nav-submod: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "nav-submod: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/get/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink (jab's upward be/-scan).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export BE JABC BEDIR

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# URI-016: a PROJECT ROOT at $WORK (rs_work_root seeds its `.be` anchor and echoes
# `work/`) holding `parent` — the //parent tree (`//parent` == <root>/work/parent
# per [/wiki/URI] step 2) — with a nested `sub` worktree.  The root is DETECTED by
# the cwd climb (core/resolve_hash.js::projectRoot), never named by an env var.
_WORKD=$(rs_work_root "$WORK")
PAR="$_WORKD/parent"

# parent: a colocated primary store (pre-made `.be` shield, then a commit).
mkdir -p "$PAR/.be"
( cd "$PAR" && printf 'PARENT-A\n' > a.txt \
    && "$JABC" post 'parent base' >/dev/null 2>&1 ) || _fail "parent seed failed"

# sub: a SECONDARY worktree nested INSIDE parent — its `.be` is a FILE redirect
# to the parent store (exactly a mounted submodule's anchor shape).  Cloned over
# a local `file:` source, NO wire.
mkdir -p "$PAR/sub"
( cd "$PAR/sub" && "$JABC" get "file:$PAR/.be?/" >/dev/null 2>&1 ) \
    || _fail "sub secondary clone failed"
[ -f "$PAR/sub/.be" ] || _fail "sub/.be is not a FILE redirect (setup broke)"

# Snapshot the SUB's `.be` and the PARENT's wtlog before the nav get.
cp "$PAR/sub/.be" "$WORK/sub.before"
par_before=$(wc -l < "$PAR/.be/wtlog")

# THE ACT: a bare `:get` under the `//parent` nav context, cwd = the sub.
if ( cd "$PAR/sub" && "$JABC" get '//parent' ) >"$WORK/get.out" 2>&1; then
    :
else
    _fail "(exit) get //parent from the sub FAILED (must refresh the context tree):
$(cat "$WORK/get.out")"
fi

# (1) THE INVARIANT: the SUB's `.be` wtlog is BYTE-IDENTICAL — get wrote NOTHING
#     into the submodule cwd.
if ! cmp -s "$WORK/sub.before" "$PAR/sub/.be"; then
    _fail "(1) get //parent MUTATED the sub's .be (cloned into the submodule cwd):
$(cat "$WORK/get.out")"
fi
echo "ok: sub/.be untouched by get //parent"

# (2) POSITIVE: the CONTEXT tree (parent) was actually refreshed — its wtlog
#     gained the `get ?#tip` row (inRepoSeed on be.repo, not a submodule clone).
par_after=$(wc -l < "$PAR/.be/wtlog")
[ "$par_after" -gt "$par_before" ] \
    || _fail "(2) parent wtlog did NOT grow — the context tree was not refreshed
(before=$par_before after=$par_after):
$(cat "$WORK/get.out")"
echo "ok: //parent refreshed the context tree (parent wtlog $par_before -> $par_after)"

echo "PASS [$NAME]"
