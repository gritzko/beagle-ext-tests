#!/bin/sh
# test/post/fetch-refless — POST-027 BUG-7: wire.fetch's spawn path leaked the
# child's stdin write-end (wfd) when pickWant threw ("peer advertised no usable
# ref"): the spawned upload-pack never saw EOF and io.reap deadlocked forever
# (the get/be + serve/uploadpack "Timeout" hang).  Pin: a `jab get` against a
# REFLESS post-seeded store must FAIL FAST (rc nonzero, "no usable ref"-class
# error) and leave NO orphaned upload-pack child.  Local jab-to-jab wire
# (KEEPER_BIN=jab, the serve/uploadpack shape) — native-free, no ssh.  The
# invocation rides a `timeout 15` watchdog so the suite itself can never hang.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)            # test/post/fetch-refless
_ROOT=$(cd "$_CASE/../.." && pwd)               # repo root (test/)
JAB=${JABC:-${BIN:+$BIN/jab}}
JAB=${JAB:-$(command -v jab || true)}
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "SKIP [fetch-refless] no $BEDIR/main.js" >&2; exit 0; }
[ -n "$JAB" ] && [ -x "$JAB" ] || { echo "SKIP [fetch-refless] no jab (set BIN=)" >&2; exit 0; }
command -v timeout >/dev/null 2>&1 || { echo "SKIP [fetch-refless] no timeout"; exit 0; }

# The wire runs jab-to-jab: the `be:` local-exec spawns `jab upload-pack`.
export KEEPER_BIN="$JAB"
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"
WORK="$TMP/$$/post-fetch-refless"
rm -rf "$WORK"; mkdir -p "$WORK"
# Plant the jsrc symlink above the scratch so bareword `jab` resolves THIS
# worktree's extension (the shared/wire.js under test) via its upward scan.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [fetch-refless] $*" >&2; exit 1; }

# --- seed a store with jab post, then make it REFLESS deterministically ----
SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A\n' > a.txt
"$JAB" post 'c1' >/dev/null 2>&1 || _fail "jab post c1 failed"
# Truncate the refs table (+ idx sidecar) so the advert carries NO usable ref
# whatever a future `post` writes — the pinned path is the CLIENT-side throw.
: > .be/refs; rm -f .be/.refs.idx

# --- the pinned invocation: must FAIL FAST, never hang ---------------------
DST="$WORK/dst"; mkdir -p "$DST"
S=$(date +%s); rc=0
( cd "$DST" && timeout 15 "$JAB" get "be:$SRC/.be?/src" ) \
    >"$WORK/get.out" 2>"$WORK/get.err" || rc=$?
E=$(date +%s)
[ "$rc" -ne 0 ] || _fail "refless get unexpectedly succeeded"
if [ "$rc" -eq 124 ] || [ "$rc" -eq 143 ]; then
    cat "$WORK/get.err" >&2
    _fail "refless get HUNG until the watchdog (BUG-7 wfd leak regressed)"
fi
[ $((E - S)) -le 10 ] || _fail "refless get took $((E - S))s (must fail fast)"
grep -q "no usable ref" "$WORK/get.err" \
    || { cat "$WORK/get.err" >&2; _fail "expected a 'no usable ref'-class error"; }

# --- no orphaned upload-pack child left behind ------------------------------
# The child's argv carries the $WORK-rooted serve path, so the probe targets
# ONLY this case's spawn (a parallel ctest run never false-positives it).
sleep 1
if ps -ef 2>/dev/null | grep -v grep | grep "upload-pack" | grep -q "$WORK"; then
    ps -ef 2>/dev/null | grep -v grep | grep "upload-pack" >&2
    _fail "orphaned upload-pack child survived the fetch"
fi

echo "PASS [fetch-refless]"
