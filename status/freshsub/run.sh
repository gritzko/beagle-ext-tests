#!/bin/sh
# test/status/freshsub — PUT-011 (ruling 2026-07-18): a mounted, non-ignored,
# `.gitmodules`-declared sub with NO baseline 160000 gitlink and NO staged bump
# (the live journal/jab shape) MUST show in the parent hunk as ONE wt-created
# gitlink row `...o <sub>` — the wt scan keeps the mount dir itself, only its
# contents stay hidden.  RED before the fix: wtScan dropped the whole nested-
# repo prefix INCLUDING the dir, and every mount-row emitter keyed off baseline
# gitlinks only, so the sub was invisible (and `put <sub>` PUTNONEd blind).
# Legs: (a) the `...o` row appears, sub files hidden; (b) a staged pin bump
# keeps ONE row (no dupe); (c) a gitignored mount stays hidden.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/status/freshsub
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "status/freshsub: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "status/freshsub: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=freshsub
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

# --- parent baseline: main.c + .gitmodules declaring vendor/sub (NO gitlink) --
WT="$WORK/wt"; mkdir -p "$WT/.be"
cd "$WT"
printf 'int main(void){return 0;}\n' > main.c
cat > .gitmodules <<EOF
[submodule "vendor/sub"]
	path = vendor/sub
	url = file://$WORK/nowhere?/sub
EOF
"$BE" post 'base' >/dev/null 2>&1 || _fail "could not seed the parent baseline"

# --- mount vendor/sub as a PRIMARY nested wt (own .be dir + wtlog), no pin ----
mkdir -p vendor/sub/.be
( cd vendor/sub && printf 'sub payload\n' > lib.c \
    && "$BE" post '#sub initial' ) >/dev/null 2>&1 || _fail "sub seed post"
[ -f vendor/sub/.be/wtlog ] || _fail "fixture: sub .be/wtlog missing"

# The PARENT hunk only (the recursion's `status vendor/sub` hunk starts a new
# banner) — slice everything before the first sub banner.
_parent() { awk '/^status vendor\/sub/{exit} {print}' "$1"; }

# --- leg (a): the never-pinned mount shows as ONE `...o vendor/sub` row -------
( cd "$WT" && "$JABC" status --plain ) >"$WORK/st1.all" 2>"$WORK/st1.err" \
    || _fail "status failed: $(cat "$WORK/st1.err")"
_parent "$WORK/st1.all" > "$WORK/st1"
have "$WORK/st1" '\.\.\.o vendor/sub$' "never-pinned mount: no \`...o vendor/sub\` row (RED pre-fix)"
miss "$WORK/st1" 'vendor/sub/lib\.c'   "sub interior file leaked into the parent hunk"
[ "$(grep -cE '(^|[[:space:]])vendor/sub$' "$WORK/st1")" = 1 ] \
    || { cat "$WORK/st1" >&2; _fail "expected exactly ONE vendor/sub row"; }

# --- leg (b): a staged pin bump (`put <sub>#<tip>` row) keeps ONE row ---------
SUBTIP=$(awk -F'#' '/post/{t=$2} END{print t}' "$WT/vendor/sub/.be/wtlog")
[ -n "$SUBTIP" ] || _fail "fixture: no sub tip in sub wtlog"
cat > "$WORK/.pinrow.js" <<'EOF'
const ulog = require(process.argv[2] + "/shared/ulog.js");
ulog.append(process.argv[3], [{ verb: "put",
  uri: URI.make(undefined, undefined, "vendor/sub", undefined, process.argv[4]) }]);
EOF
"$JABC" "$WORK/.pinrow.js" "$BEDIR" "$WT/.be/wtlog" "$SUBTIP" >/dev/null 2>&1 \
    || _fail "could not stage the pin bump row"
( cd "$WT" && "$JABC" status --plain ) >"$WORK/st2.all" 2>"$WORK/st2.err" \
    || _fail "status (staged) failed: $(cat "$WORK/st2.err")"
_parent "$WORK/st2.all" > "$WORK/st2"
# Staged spells UPPERCASE in the plain render (`...O`, cf `...V` staged puts).
have "$WORK/st2" '\.\.\.O vendor/sub$' "staged pin: the staged \`...O vendor/sub\` row vanished"
[ "$(grep -cE '(^|[[:space:]])vendor/sub$' "$WORK/st2")" = 1 ] \
    || { cat "$WORK/st2" >&2; _fail "staged pin: expected exactly ONE vendor/sub row (dupe?)"; }

# --- leg (c): a gitignored mount stays hidden ---------------------------------
mkdir -p ignored/sub2/.be
( cd ignored/sub2 && printf 'x\n' > x.c && "$BE" post '#sub2' ) >/dev/null 2>&1 \
    || _fail "sub2 seed post"
printf 'ignored/\n' > "$WT/.gitignore"
( cd "$WT" && "$JABC" status --plain ) >"$WORK/st3.all" 2>"$WORK/st3.err" \
    || _fail "status (ignored) failed: $(cat "$WORK/st3.err")"
_parent "$WORK/st3.all" > "$WORK/st3"
miss "$WORK/st3" 'ignored/sub2' "a gitignored mount must stay hidden"

echo "PASS [status/$NAME]"
