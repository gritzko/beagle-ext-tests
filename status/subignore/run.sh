#!/bin/sh
# test/status/subignore — STATUS-018 (the JS twin of STATUS-002): the ignore
# chain must CROSS the sub boundary, so a parent's `.gitignore` governs a
# DECLARED sub's paths.  RED before the fix: `shared/util/ignore.js` load()
# stopped its upward walk at the first `.be`/`.git`, so `jab status <sub>`
# flooded with the sub's build junk that the parent's `build/` already covers.
# The crossing is declaration-gated (SUBS-045): an enclosing repo that does NOT
# declare the wt in `.gitmodules` must still NOT swallow it (the BE-031 hive,
# leg c) — the same guard test/status/hive keeps for a non-repo enclosing dir.
# Registered by the be/test glob as be-js-status-subignore — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/status/subignore
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "status/subignore: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "status/subignore: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=subignore
WORK="$TMP/$$/status/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `jsrc -> <be/>` shard symlink so bareword `jab status`
# resolves the extension via jab's upward be/-scan from the scratch cwd.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [status/$NAME] $*" >&2; exit 1; }
have() { grep -qE "$2" "$1" || { echo "--- $1 ---"; cat -A "$1" >&2; _fail "$3 (expected /$2/)"; }; }
miss() { grep -qE "$2" "$1" && { echo "--- $1 ---"; cat -A "$1" >&2; _fail "$3 (unexpected /$2/)"; } || true; }

# --- parent baseline: `build/` ignored, `sub` DECLARED in .gitmodules ---------
WT="$WORK/wt"; mkdir -p "$WT/.be"
cd "$WT"
printf 'int main(void){return 0;}\n' > main.c
printf 'build/\n' > .gitignore
cat > .gitmodules <<EOF
[submodule "sub"]
	path = sub
	url = file://$WORK/nowhere?/sub
EOF
"$BE" post 'base' >/dev/null 2>&1 || _fail "could not seed the parent baseline"

# --- the sub: own .be + own `.gitignore` (own/), plus junk the PARENT ignores -
mkdir -p sub/.be
( cd sub && printf 'sub payload\n' > lib.c && printf 'own/\n' > .gitignore \
    && "$BE" post '#sub initial' ) >/dev/null 2>&1 || _fail "sub seed post"
mkdir -p sub/build sub/own
printf 'junk\n'  > sub/build/CMakeCache.txt
printf 'junk\n'  > sub/own/noise.txt
printf 'edited\n' > sub/lib.c            # a real row, proves the scan ran

# --- leg (a): the parent's `build/` reaches into the declared sub -------------
( cd "$WT" && "$JABC" status sub --plain ) >"$WORK/sub.out" 2>"$WORK/sub.err" \
    || _fail "status sub failed: $(cat "$WORK/sub.err")"
have "$WORK/sub.out" 'sub/lib\.c'  "the sub scan emitted no rows at all"
miss "$WORK/sub.out" 'sub/build/'  "parent's \`build/\` never reached the sub (RED pre-fix)"

# --- leg (b): the sub's OWN `.gitignore` still applies ------------------------
miss "$WORK/sub.out" 'sub/own/'    "the sub's own .gitignore was lost"

# --- leg (c): an UNDECLARED enclosing repo must NOT swallow the wt (BE-031) ---
# Same shape as test/status/hive, but the enclosing dir is itself a repo (.be):
# crossing must be gated on the `.gitmodules` declaration, not on `.be` alone.
OUTER="$WORK/outer"; OWT="$OUTER/work/WT"
mkdir -p "$OUTER/.be" "$OWT/.be"
printf 'work/\n' > "$OUTER/.gitignore"
( cd "$OWT" && printf 'seed\n' > a.txt && "$BE" post 'seed commit' ) >/dev/null 2>&1 \
    || _fail "hive-shape seed post"
( cd "$OWT" && "$JABC" status --plain ) >"$WORK/hive.out" 2>"$WORK/hive.err" \
    || _fail "hive-shape status failed: $(cat "$WORK/hive.err")"
miss "$WORK/hive.out" '\.\.\.x a\.txt' "an undeclared enclosing repo swallowed the wt"

echo "PASS [status/$NAME]"
