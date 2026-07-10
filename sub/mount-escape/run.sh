#!/bin/sh
# BE-026 test/sub/mount-escape — a checked-out `.gitmodules` whose submodule
# `path=` value CLIMBS out of the worktree (`../outside`, `/etc`, `../../etc`)
# must be REFUSED, never stat'd or be.find'd.  core/recurse.js used to build the
# mount path by RAW CONCAT (`<wt>/<subpath>/.be`) and feed it to lstat/stat/
# be.find with NO confinement, so a crafted `path = ../outside` reached a `.be`
# OUTSIDE the wt (a path-traversal escape, the JS twin of BE-011).  The fix
# confines every subpath via shared/util/path.js `wtJoin` (throws NAVESCAPE on a
# climb, caught → no-mount) and DROPS non-`safeRel` `path` entries at the source
# (shared/gitmodules.js parse).  RED before the fix (escape), GREEN after.  The
# probe drives core/recurse.js::isMount + shared/gitmodules.js::paths DIRECTLY —
# a minimal in-process repro, no clone/keeper.  JS-ONLY; SUT=recurse.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/sub/mount-escape
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
# TEST-003: jab-only — native `be` is RETIRED; locate jab, alias BE=$JABC.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "mount-escape: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "mount-escape: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/sub/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
# jab resolves its JS extension via an upward be/-scan; plant the shard symlink.
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export BE JABC BEDIR

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# --- fixture: a wt with a poisoned `.gitmodules` + an OUTSIDE `.be` marker ----
# $WORK/wt        the worktree (its `.be/` shield = the confinement boundary)
# $WORK/wt/good   a LEGIT mounted sub (a regular `good/.be` file) — positive ctl
# $WORK/outside   a SIBLING dir with a regular `.be` FILE, OUTSIDE the wt: an
#                 unconfined `path = ../outside` would stat/adopt IT (the escape)
_wt="$WORK/wt"; mkdir -p "$_wt/.be" "$_wt/good"
: > "$_wt/good/.be"                               # legit in-tree mount
_out="$WORK/outside"; mkdir -p "$_out"
: > "$_out/.be"                                   # escape target (outside the wt)
cat > "$_wt/.gitmodules" <<'EOF'
[submodule "esc"]
	path = ../outside
[submodule "good"]
	path = good
[submodule "abs"]
	path = /etc
[submodule "dotdot"]
	path = ../../etc
EOF

# --- probe: drive recurse.isMount + gitmodules.paths directly -----------------
cat > "$WORK/.probe.js" <<'EOF'
"use strict";
const BEDIR   = process.argv[3];
const recurse = require(BEDIR + "/core/recurse.js");
const gm      = require(BEDIR + "/shared/gitmodules.js");
const wt = process.argv[2];
function w(s){ const u=utf8.Encode(s+"\n"); const b=io.buf(u.length+8); b.feed(u); io.write(1,b); }
w("PATHS=" + JSON.stringify(gm.paths(wt)));       // source: dropped non-safeRel?
w("MOUNT_esc="    + recurse.isMount(wt, "../outside")); // use: `..` escape gate
w("MOUNT_dotdot=" + recurse.isMount(wt, "../../etc"));
w("MOUNT_abs="    + recurse.isMount(wt, "/etc"));
w("MOUNT_good="   + recurse.isMount(wt, "good"));       // legit mount still YES
EOF
"$JABC" "$WORK/.probe.js" "$_wt" "$BEDIR" >"$WORK/probe.out" 2>"$WORK/probe.err" \
    || { echo "--- probe.err ---"; cat "$WORK/probe.err"; _fail "probe crashed"; }

_get() { sed -n "s/^$1=//p" "$WORK/probe.out" | head -n1; }

# (a) the OUTSIDE `.be` must NOT be reachable via `path = ../outside`: isMount
#     confines the subpath (wtJoin → NAVESCAPE), refusing it as a no-mount.
[ "$(_get MOUNT_esc)" = "false" ] \
    || { echo "--- probe.out ---"; cat "$WORK/probe.out"; \
         _fail "(a) isMount('../outside') did not refuse — ESCAPED the wt to $_out/.be"; }
[ "$(_get MOUNT_dotdot)" = "false" ] \
    || _fail "(a) isMount('../../etc') did not refuse (escape)"
[ "$(_get MOUNT_abs)" = "false" ] \
    || _fail "(a) isMount('/etc') did not refuse (absolute escape)"
echo "ok: recurse.isMount refuses ..-climbing / absolute submodule paths (no wt escape)"

# (b) the source gate: gitmodules.parse DROPS the non-safeRel entries, so a
#     poisoned path never even reaches the walk.  Only the legit `good` remains.
_paths=$(_get PATHS)
case "$_paths" in
    *'../outside'*|*'../../etc'*|*'"/etc"'*)
        _fail "(b) gitmodules.paths kept a non-safeRel entry: $_paths" ;;
esac
case "$_paths" in
    *'"good"'*) ;;
    *) _fail "(b) gitmodules.paths dropped the LEGIT 'good' sub: $_paths" ;;
esac
echo "ok: gitmodules.parse drops non-safeRel path= at the source ($_paths)"

# (c) positive control: a legit in-tree mount is STILL recognised (no over-block).
[ "$(_get MOUNT_good)" = "true" ] \
    || { echo "--- probe.out ---"; cat "$WORK/probe.out"; \
         _fail "(c) isMount('good') refused a LEGIT in-tree mount (over-blocked)"; }
echo "ok: a legit in-tree submodule mount is still recognised"

echo "PASS [$NAME]"
