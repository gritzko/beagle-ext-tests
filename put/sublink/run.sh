#!/bin/sh
# test/put/sublink — PUT-011 (ruling 2026-07-18): the trailing slash splits the
# two sub puts.  `put <sub>` (bare) stages ONLY the parent gitlink bump row
# `put <sub>#<subCurTip>` — INCLUDING the fresh-add (a declared+mounted sub
# with no baseline 160000 pin stages its FIRST pin; the BE-049 no-pin arm was
# a silent no-op → PUTNONE).  `put <sub>/` (slash) stages ONLY inside the sub,
# no parent bump.  A nothing-to-stage / undeclared refusal must speak plain
# words, not a bare code.  RED pre-fix on legs (a), (c), (d).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/put/sublink
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "put/sublink: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "put/sublink: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=sublink
WORK="$TMP/$$/put/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `jsrc -> <be/>` shard symlink (bareword resolution).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [put/$NAME] $*" >&2; exit 1; }

# Build one parent+sub fixture under $1: parent baseline commit, .gitmodules
# declaring vendor/sub ($2 = "declared" | "bare"), the sub mounted as a PRIMARY
# nested wt (own .be dir + wtlog) with one commit — NO gitlink pin anywhere.
setup() {
  mkdir -p "$1/.be"; cd "$1"
  printf 'int main(void){return 0;}\n' > main.c
  if [ "$2" = declared ]; then cat > .gitmodules <<EOF
[submodule "vendor/sub"]
	path = vendor/sub
	url = file://$1/nowhere?/sub
EOF
  fi
  "$BE" post 'base' >/dev/null 2>&1 || _fail "parent seed post in $1"
  mkdir -p vendor/sub/.be
  ( cd vendor/sub && printf 'sub payload\n' > lib.c \
      && "$BE" post '#sub initial' ) >/dev/null 2>&1 || _fail "sub seed post in $1"
  [ -f vendor/sub/.be/wtlog ] || _fail "fixture: sub wtlog missing in $1"
}
subtip() { awk -F'#' '/post/{t=$2} END{print t}' "$1/vendor/sub/.be/wtlog"; }

# --- leg (a): fresh-add — bare `put vendor/sub` stages the FIRST pin ---------
A="$WORK/a"; setup "$A" declared
TIP=$(subtip "$A"); [ -n "$TIP" ] || _fail "fixture: no sub tip"
SUBLOG0=$(wc -l < "$A/vendor/sub/.be/wtlog")
( cd "$A" && "$JABC" put vendor/sub ) >"$WORK/a.out" 2>"$WORK/a.err" \
    || _fail "(a) fresh-add put vendor/sub FAILED (RED pre-fix: silent no-pin no-op): $(cat "$WORK/a.err")"
grep -qE "put[[:space:]]+vendor/sub#$TIP" "$A/.be/wtlog" \
    || _fail "(a) first-pin bump row missing from the parent wtlog: $(tail -3 "$A/.be/wtlog")"
[ "$(wc -l < "$A/vendor/sub/.be/wtlog")" = "$SUBLOG0" ] \
    || _fail "(a) bare put leaked INSIDE the sub (sub wtlog grew): $(tail -3 "$A/vendor/sub/.be/wtlog")"
( cd "$A" && "$JABC" status --plain ) >"$WORK/a.st" 2>&1 || _fail "(a) status failed"
awk '/^status vendor\/sub/{exit} {print}' "$WORK/a.st" > "$WORK/a.par"
grep -qE '\.\.\.O vendor/sub$' "$WORK/a.par" \
    || { cat "$WORK/a.par" >&2; _fail "(a) staged ...O vendor/sub row missing"; }
[ "$(grep -cE '(^|[[:space:]])vendor/sub$' "$WORK/a.par")" = 1 ] \
    || { cat "$WORK/a.par" >&2; _fail "(a) expected exactly ONE vendor/sub row"; }

# --- leg (b): slash — `put vendor/sub/` stages inside, NO parent bump --------
B="$WORK/b"; setup "$B" declared
( cd "$B/vendor/sub" && printf 'sub payload v2\n' > lib.c ) || _fail "(b) dirty sub"
( cd "$B" && "$JABC" put vendor/sub/ ) >"$WORK/b.out" 2>"$WORK/b.err" \
    || _fail "(b) put vendor/sub/ failed: $(cat "$WORK/b.err")"
grep -qE "put[[:space:]]+lib\.c" "$B/vendor/sub/.be/wtlog" \
    || _fail "(b) lib.c not staged inside the sub: $(tail -3 "$B/vendor/sub/.be/wtlog")"
grep -qE "put[[:space:]]+vendor/sub#" "$B/.be/wtlog" \
    && _fail "(b) slash form staged a parent gitlink bump: $(tail -3 "$B/.be/wtlog")" || true

# --- leg (c): nothing-to-stage speaks words, not a bare code -----------------
rc=0
( cd "$A" && "$JABC" put vendor/sub ) >"$WORK/c.out" 2>"$WORK/c.err" || rc=$?
[ "$rc" != 0 ] || _fail "(c) repeat put vendor/sub exited 0 (pin already at tip)"
cat "$WORK/c.out" "$WORK/c.err" > "$WORK/c.all"
grep -qi "nothing to stage\|already at" "$WORK/c.all" \
    || { cat "$WORK/c.all" >&2; _fail "(c) refusal does not speak plain words"; }
grep -qE '(^|[^A-Z])PUTNONE([^A-Z]|$)' "$WORK/c.all" \
    && { cat "$WORK/c.all" >&2; _fail "(c) refusal leaks the bare code"; } || true

# --- leg (d): fresh-add of an UNDECLARED mount refuses in words --------------
D="$WORK/d"; setup "$D" bare
rc=0
( cd "$D" && "$JABC" put vendor/sub ) >"$WORK/d.out" 2>"$WORK/d.err" || rc=$?
[ "$rc" != 0 ] || _fail "(d) undeclared fresh-add exited 0"
cat "$WORK/d.out" "$WORK/d.err" > "$WORK/d.all"
grep -qi "gitmodules" "$WORK/d.all" \
    || { cat "$WORK/d.all" >&2; _fail "(d) refusal does not name .gitmodules"; }
grep -qE "put[[:space:]]+vendor/sub#" "$D/.be/wtlog" \
    && _fail "(d) undeclared fresh-add staged a bump anyway" || true

echo "PASS [put/$NAME]"
