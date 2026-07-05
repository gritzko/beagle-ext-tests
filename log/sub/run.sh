#!/bin/sh
# test/log/sub — LOG-002: `jab log:<sub>` must log the SUBMODULE's OWN history,
# not the super-repo's gitlink-bump line.  Before the fix log.js path-filtered
# the CURRENT repo (so `jab log:vendor/sub` listed only the parent commit that
# bumped the `vendor/sub` gitlink); the fix descends into the sub MOUNT via
# shared/subs.js — the SAME seam tree.js/status.js use — and walks the sub's
# own tips.  Mirrors C `be log:<sub>` (the parity target).
#
# Fixture (pure `be`, no git, modelled on test/parity/status-subs build_fixture):
# a parent wt that MOUNTS + COMMITS a gitlink at vendor/sub, where the sub store
# has THREE of its own commits.  Asserts byte-parity of `jab log:vendor/sub`
# (and `log:./vendor/sub`) with BOTH C `be log:vendor/sub` AND
# `cd vendor/sub && jab log:`, and that `log:vendor/sub/<file>` logs WITHIN the
# sub.  RED today (the sub history is the super-repo's `mount sub` line); GREEN
# after.  Registered by the be/test glob as be-js-log-sub — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/log/sub
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "log/sub: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-$_BIN/jab}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "log/sub: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "log/sub: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=sub
WORK="$TMP/$$/log/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink so bareword `jab log`
# resolves the extension via jab's upward be/-scan from the worktree cwd.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [log/$NAME] $*" >&2; exit 1; }

# --- mounted-sub fixture (pure be, à la parity/status-subs build_fixture) ----
PWT="$WORK/par"; SUBSTORE="$WORK/substore"
rm -rf "$PWT" "$SUBSTORE"
mkdir -p "$SUBSTORE/.be" "$PWT/.be"

# sub store: THREE of its OWN commits (the history the sub log must show).
( cd "$SUBSTORE"
  printf 'a\n' > lib.c; printf 'h\n' > helper.c
  "$BE" put lib.c helper.c >/dev/null 2>&1; "$BE" post '#sub c1' >/dev/null 2>&1
  printf 'b\n' > lib.c; "$BE" put lib.c >/dev/null 2>&1; "$BE" post '#sub c2' >/dev/null 2>&1
  printf 'c\n' > lib.c; "$BE" put lib.c >/dev/null 2>&1; "$BE" post '#sub c3' >/dev/null 2>&1 ) \
    || _fail "sub setup"
SUBTIP=$(awk -F'\t' '$2=="post"{l=$3} END{h=l;sub(/^.*#/,"",h);print h}' "$SUBSTORE/.be/wtlog")
case "$SUBTIP" in ????????????????????????????????????????) ;; *) _fail "sub tip not 40-hex: '$SUBTIP'";; esac

# parent store: a baseline, then MOUNT + COMMIT the sub gitlink at vendor/sub.
( cd "$PWT"
  printf 'int main(void){return 0;}\n' > main.c
  "$BE" put main.c >/dev/null 2>&1; "$BE" post '#parent main' >/dev/null 2>&1 ) || _fail "parent setup"
( cd "$PWT"
  cat > .gitmodules <<EOF
[submodule "vendor/sub"]
	path = vendor/sub
	url = file://$SUBSTORE/.be?/substore
EOF
  mkdir -p vendor/sub
  RONTS=$(awk -F'\t' 'NR==1{print $1; exit}' .be/wtlog)
  printf '%s\tget\tfile:%s/.be/?/substore#%s\n' "$RONTS" "$SUBSTORE" "$SUBTIP" > vendor/sub/.be
  printf 'c\n' > vendor/sub/lib.c; printf 'h\n' > vendor/sub/helper.c
  "$BE" put .gitmodules >/dev/null 2>&1
  "$BE" put vendor/sub  >/dev/null 2>&1
  "$BE" post '#mount sub' >/dev/null 2>&1 ) || _fail "mount sub"
[ -f "$PWT/vendor/sub/.be" ] || _fail "sub anchor not a file (mount failed)"

# Captures: C oracle, the sub run-in-place (cd sub && jab log:), the parent log.
( cd "$PWT"            && "$BE"   log:vendor/sub --plain ) >"$WORK/nat.sub"   2>/dev/null || true
( cd "$PWT"            && "$JABC" log:vendor/sub --plain ) >"$WORK/jab.sub"   2>/dev/null || true
( cd "$PWT"            && "$JABC" log:./vendor/sub --plain) >"$WORK/jab.dotsub" 2>/dev/null || true
( cd "$PWT/vendor/sub" && "$JABC" log: --plain           ) >"$WORK/jab.cdsub"  2>/dev/null || true
( cd "$PWT"            && "$JABC" log: --plain            ) >"$WORK/jab.par"    2>/dev/null || true
[ -s "$WORK/jab.sub" ] || _fail "jab log:vendor/sub emitted ZERO bytes"

# 1. THE REPRO: jab log:<sub> must list the SUB's shas, not the parent's.  The
#    parent's only gitlink-bumping commit is `mount sub`; pre-fix jab printed
#    exactly that row.  Assert the parent's tip sha8 does NOT appear in the sub
#    log, and the sub's tip sha8 DOES (RED before, GREEN after).
PARTIP8=$(awk 'NF && $1 ~ /^[0-9a-f]{8}$/ {print $1; exit}' "$WORK/jab.par")
SUBTIP8=$(printf '%s' "$SUBTIP" | cut -c1-8)
grep -q "^$SUBTIP8 " "$WORK/jab.sub" || {
    echo "--- jab log:vendor/sub ---"; cat -A "$WORK/jab.sub"
    _fail "sub tip $SUBTIP8 absent from jab log:vendor/sub (still logging the super-repo?)"; }
grep -q "^$PARTIP8 " "$WORK/jab.sub" && {
    echo "--- jab log:vendor/sub ---"; cat -A "$WORK/jab.sub"
    _fail "parent tip $PARTIP8 (the gitlink-bump) leaked into the SUB log"; } || true
echo "ok: jab log:vendor/sub lists the SUB's own commits, not the super-repo's"

# 2. Body-parity with the C oracle `be log:vendor/sub` (the history rows).
#    URI-014: the JS banner is now the WORD spell `log vendor/sub` (verb OUT of
#    the scheme); the C oracle still bakes `log:vendor/sub` (C follow-up pending),
#    so assert the JS banner shape directly + compare the banner-stripped bodies.
head -n1 "$WORK/jab.sub" | grep -qx "log vendor/sub" \
    || { echo "--- jab banner ---"; head -n1 "$WORK/jab.sub"; \
         _fail "jab log:vendor/sub banner is not the word spell 'log vendor/sub'"; }
tail -n +2 "$WORK/nat.sub" > "$WORK/nat.sub.body"
tail -n +2 "$WORK/jab.sub" > "$WORK/jab.sub.rows"
cmp -s "$WORK/nat.sub.body" "$WORK/jab.sub.rows" || {
    echo "--- native be log:vendor/sub ---"; cat -A "$WORK/nat.sub"
    echo "--- jab    log:vendor/sub ---";    cat -A "$WORK/jab.sub"
    _fail "jab log:vendor/sub rows differ from C be log:vendor/sub"; }
echo "ok: jab log:vendor/sub banner=word spell, rows byte-match C be log:vendor/sub"

# 3. The sub's body (minus the `log:<path>` banner) equals `cd sub && jab log:`.
tail -n +2 "$WORK/jab.sub"   > "$WORK/jab.sub.body"
tail -n +2 "$WORK/jab.cdsub" > "$WORK/jab.cdsub.body"
cmp -s "$WORK/jab.sub.body" "$WORK/jab.cdsub.body" || {
    echo "--- jab log:vendor/sub (body) ---"; cat -A "$WORK/jab.sub.body"
    echo "--- cd sub && jab log: (body) ---"; cat -A "$WORK/jab.cdsub.body"
    _fail "jab log:vendor/sub body differs from cd vendor/sub && jab log:"; }
echo "ok: jab log:vendor/sub == cd vendor/sub && jab log: (same sub history)"

# 4. `log:./vendor/sub` is identical to `log:vendor/sub` (the ./ form descends too).
cmp -s "$WORK/jab.sub" "$WORK/jab.dotsub" || {
    echo "--- jab log:vendor/sub ---";   cat -A "$WORK/jab.sub"
    echo "--- jab log:./vendor/sub ---"; cat -A "$WORK/jab.dotsub"
    _fail "jab log:./vendor/sub differs from jab log:vendor/sub"; }
echo "ok: jab log:./vendor/sub descends the mount too"

# 5. log:<sub>/<file> logs WITHIN the sub (strip the sub prefix, recurse) —
#    byte-parity with C be log:vendor/sub/lib.c.
( cd "$PWT" && "$BE"   log:vendor/sub/lib.c --plain ) >"$WORK/nat.file" 2>/dev/null || true
( cd "$PWT" && "$JABC" log:vendor/sub/lib.c --plain ) >"$WORK/jab.file" 2>/dev/null || true
# URI-014: word-spell banner (`log vendor/sub/lib.c`) vs C scheme form — assert
# the JS banner shape + compare the banner-stripped history rows (C follow-up).
head -n1 "$WORK/jab.file" | grep -qx "log vendor/sub/lib.c" \
    || { echo "--- jab banner ---"; head -n1 "$WORK/jab.file"; \
         _fail "jab log:vendor/sub/lib.c banner is not the word spell"; }
tail -n +2 "$WORK/nat.file" > "$WORK/nat.file.body"
tail -n +2 "$WORK/jab.file" > "$WORK/jab.file.body"
cmp -s "$WORK/nat.file.body" "$WORK/jab.file.body" || {
    echo "--- native be log:vendor/sub/lib.c ---"; cat -A "$WORK/nat.file"
    echo "--- jab    log:vendor/sub/lib.c ---";    cat -A "$WORK/jab.file"
    _fail "jab log:vendor/sub/lib.c rows differ from C (sub-relative file history)"; }
echo "ok: jab log:vendor/sub/lib.c logs the file WITHIN the sub"

# 6. NO REGRESSION: a NON-sub path keeps current-repo behaviour — byte-parity
#    with C be log:main.c.
( cd "$PWT" && "$BE"   log:main.c --plain ) >"$WORK/nat.main" 2>/dev/null || true
( cd "$PWT" && "$JABC" log:main.c --plain ) >"$WORK/jab.main" 2>/dev/null || true
# URI-014: word-spell banner (`log main.c`) vs C scheme form — assert the JS
# banner shape + compare the banner-stripped rows (C follow-up pending).
head -n1 "$WORK/jab.main" | grep -qx "log main.c" \
    || { echo "--- jab banner ---"; head -n1 "$WORK/jab.main"; \
         _fail "jab log:main.c banner is not the word spell 'log main.c'"; }
tail -n +2 "$WORK/nat.main" > "$WORK/nat.main.body"
tail -n +2 "$WORK/jab.main" > "$WORK/jab.main.body"
cmp -s "$WORK/nat.main.body" "$WORK/jab.main.body" || {
    echo "--- native be log:main.c ---"; cat -A "$WORK/nat.main"
    echo "--- jab    log:main.c ---";    cat -A "$WORK/jab.main"
    _fail "jab log:main.c (non-sub) rows differ from C (regression)"; }
echo "ok: non-sub log:main.c unchanged (no regression)"

echo "PASS [log/$NAME]"
