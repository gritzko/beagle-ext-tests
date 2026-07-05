#!/bin/sh
# test/log/subnav — SUBS-045: a DESCENDED `jab log:<sub>` row's hidden `U`
# click-target must be BASE-RELATIVE (`commit:<sub>?<sha>`), and `commit:` must
# DESCEND that `<sub>` prefix before resolving, so feeding a row's target back
# FROM THE PARENT root renders the SUB commit.  Before the fix log.js emitted a
# store-agnostic `commit:?<sha>` (no prefix) and commit.js was sub-blind, so the
# round-trip died with COMMITNONE; `cd <sub> && jab commit:?<sha>` rendered.
# Read-side twin of SUBS-039; extends the LOG-002 descendSub seam.
#
# Fixture (pure `be`, modelled on LOG-002's test/log/sub build_fixture): a parent
# wt MOUNTing + COMMITting a gitlink at vendor/sub, the sub store carrying THREE
# of its own commits.  RED before the fix (COMMITNONE from the parent), GREEN
# after.  Glob-registered by the be/test harness as be-js-log-subnav.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/log/subnav
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "log/subnav: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-$_BIN/jab}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "log/subnav: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "log/subnav: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=subnav
WORK="$TMP/$$/log/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink so bareword `jab` resolves
# the extension via jab's upward be/-scan from the worktree cwd.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [log/$NAME] $*" >&2; exit 1; }

# --- mounted-sub fixture (pure be, à la LOG-002 test/log/sub) -----------------
PWT="$WORK/par"; SUBSTORE="$WORK/substore"
rm -rf "$PWT" "$SUBSTORE"
mkdir -p "$SUBSTORE/.be" "$PWT/.be"

# sub store: THREE of its OWN commits (the history the nav must round-trip to).
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

# --- 1. EMIT: the row `U` target carries the descent prefix -------------------
# URI-014: the U-target is a `word URI` spell — `commit vendor/sub?<sha>` (verb
# OUT of the scheme).  It MUST be base-relative, NOT the bare `commit ?<sha>`.
UTGT=$( ( cd "$PWT" && "$JABC" log:vendor/sub --tlv ) 2>/dev/null \
        | strings | grep -o 'commit [0-9a-zA-Z/]*?[0-9a-f]\{40\}' | head -1 )
[ -n "$UTGT" ] || _fail "no commit U-target found in jab log:vendor/sub --tlv"
NAVSHA=${UTGT##*\?}
case "$UTGT" in
  "commit vendor/sub?"*) echo "ok: EMIT — descended row links to $UTGT (base-relative prefix)";;
  "commit ?"*) _fail "EMIT still store-agnostic: $UTGT (missing the vendor/sub prefix)";;
  *) _fail "unexpected U-target shape: $UTGT";;
esac

# --- 2. RESOLVE round-trip: feed the target back FROM THE PARENT root ---------
# URI-014: a word spell rides as argv — UNQUOTED $UTGT shell-splits into `commit`
# + `vendor/sub?<sha>`, exactly as the pager's spellCall→argline splits a click.
# RED before the fix: commit.js was sub-blind → COMMITNONE.  GREEN after.
( cd "$PWT" && "$JABC" $UTGT --plain ) >"$WORK/nav.parent" 2>"$WORK/nav.err" \
  && RC=0 || RC=$?
[ "$RC" = 0 ] || { echo "--- stderr ---"; cat "$WORK/nav.err"; \
    _fail "round-trip $UTGT from parent root failed (rc=$RC) — sub-blind commit view"; }
[ -s "$WORK/nav.parent" ] || _fail "round-trip $UTGT rendered ZERO bytes"
grep -q "^commit $NAVSHA" "$WORK/nav.parent" \
  || { echo "--- nav.parent ---"; cat -A "$WORK/nav.parent"; \
       _fail "round-trip did not render the SUB commit $NAVSHA"; }
echo "ok: RESOLVE — $UTGT from the parent root renders the sub commit $NAVSHA"

# --- 3. PARITY: == `cd vendor/sub && jab commit:?<sha>` -----------------------
( cd "$PWT/vendor/sub" && "$JABC" "commit:?$NAVSHA" --plain ) >"$WORK/nav.cdsub" 2>/dev/null || true
cmp -s "$WORK/nav.parent" "$WORK/nav.cdsub" \
  || { echo "--- parent commit:vendor/sub?sha ---"; cat -A "$WORK/nav.parent"; \
       echo "--- cd sub && jab commit:?sha ---";    cat -A "$WORK/nav.cdsub"; \
       _fail "prefixed round-trip differs from cd vendor/sub && jab commit:?<sha>"; }
echo "ok: PARITY — commit:vendor/sub?<sha> == cd vendor/sub && jab commit:?<sha>"

# --- 4. cwd-INVARIANT: cd sub && jab log: links stay UNprefixed + round-trip --
# From inside the sub the base IS the sub — descent delta is "" — so the link
# must stay `commit:?<sha>` (prefixing `vendor/sub` there would be WRONG).
CDUTGT=$( ( cd "$PWT/vendor/sub" && "$JABC" log: --tlv ) 2>/dev/null \
          | strings | grep -o 'commit [0-9a-zA-Z/]*?[0-9a-f]\{40\}' | head -1 )
[ -n "$CDUTGT" ] || _fail "no commit U-target in cd sub && jab log: --tlv"
case "$CDUTGT" in
  "commit ?"*) echo "ok: cwd-INVARIANT — cd sub link stays unprefixed ($CDUTGT)";;
  *) _fail "cwd-invariant BROKEN: cd sub link is prefixed: $CDUTGT";;
esac
CDNAVSHA=${CDUTGT##*\?}
( cd "$PWT/vendor/sub" && "$JABC" $CDUTGT --plain ) >"$WORK/cd.nav" 2>/dev/null || true
grep -q "^commit $CDNAVSHA" "$WORK/cd.nav" \
  || _fail "cd sub unprefixed link did not round-trip"
echo "ok: cwd-INVARIANT — the unprefixed link round-trips inside the sub"

# --- 5. NO REGRESSION: top-level log→commit round-trip is unprefixed ----------
PARUTGT=$( ( cd "$PWT" && "$JABC" log: --tlv ) 2>/dev/null \
           | strings | grep -o 'commit [0-9a-zA-Z/]*?[0-9a-f]\{40\}' | head -1 )
[ -n "$PARUTGT" ] || _fail "no commit U-target in jab log: (parent)"
case "$PARUTGT" in
  "commit ?"*) : ;;
  *) _fail "non-descended top log link got a spurious prefix: $PARUTGT";;
esac
PARNAVSHA=${PARUTGT##*\?}
( cd "$PWT" && "$JABC" $PARUTGT --plain ) >"$WORK/par.nav" 2>/dev/null || true
grep -q "^commit $PARNAVSHA" "$WORK/par.nav" \
  || _fail "top-level commit:?<sha> round-trip regressed"
echo "ok: NO REGRESSION — top-level log→commit round-trip unprefixed & green"

# --- 6. NON-SUB path: commit:<sha> unchanged (a bare hashlet, no descent) -----
( cd "$PWT" && "$JABC" "commit:?$PARNAVSHA" --plain ) >"$WORK/par.q" 2>/dev/null || true
cmp -s "$WORK/par.nav" "$WORK/par.q" \
  || _fail "commit:?<top-sha> differs from the top log link (non-sub regression)"
echo "ok: NON-SUB — commit:?<top-sha> unchanged"

echo "PASS [log/$NAME]"
