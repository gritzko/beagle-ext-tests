#!/bin/sh
# test/work/pinahbeh — WORK-012: a work wt tracking a slashLESS PIN-FORM URI
# (`get ///sub#…`, the de-jure gitlink pin) must read its ahbeh vs the PARENT's
# committed gitlink pin of that mount — NOT vs the parent's own live tip.  The
# old code collapsed a pin-form track to the parent node and fed nodeTip(parent)
# (the PARENT repo's own sha) into the tracked WT's shard keeper: a cross-repo
# ancestor walk that renders garbage (`[+N]`/`[-1]`).  Two-repo fixture: a parent
# META that COMMITS a 160000 gitlink of mount `sub` at pin S, plus a DECLARED but
# UNPINNED mount `alt`.  PINW tracks `///sub#S` (in sync with the pin) -> 0/0, no
# counter; ALTW tracks `///alt#A` (no de-jure pin) -> no counts, like the mount
# repo rows' `mc = pin ? … : null`.  RED (pre-fix): both rows carry a counter
# (parent-tip cross-repo garbage).  GREEN: neither does.  POSIX sh.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/work/pinahbeh
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "work/pinahbeh: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "work/pinahbeh: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=pinahbeh
WORK="$TMP/$$/work/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the jsrc symlink (bareword `jab work` resolves via jab's
# upward jsrc/-scan from the fixture cwd).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [work/$NAME] $*" >&2; exit 1; }
_sha40() { grep -o '[0-9a-f]\{40\}' "$1" | sed -n "$2p"; }

# --- the two-repo FIXTURE (real colocated stores, jab-posted commits) --------
META="$WORK/meta"
mkdir -p "$META/.be" "$META/sub/.be" "$META/alt/.be" "$META/work"
cat > "$META/.gitmodules" <<'EOF'
[submodule "sub"]
	path = sub
	url = git@github.com:nowhere/subproj.git
[submodule "alt"]
	path = alt
	url = git@github.com:nowhere/altproj.git
EOF
( cd "$META/sub" && printf 's1\n' > s.txt && "$BE" post 'sub one' ) \
    >/dev/null 2>&1 || _fail "seed sub"
( cd "$META/alt" && printf 'a1\n' > a.txt && "$BE" post 'alt one' ) \
    >/dev/null 2>&1 || _fail "seed alt"
SSHA=$(_sha40 "$META/sub/.be/wtlog" 1)           # sub tip == the pin
ASHA=$(_sha40 "$META/alt/.be/wtlog" 1)           # alt tip (unpinned)
[ -n "$SSHA" ] && [ -n "$ASHA" ] || _fail "sub/alt sha capture"
# Trunks so the `?`-anchored tracker `.be` rows resolve a store.
printf '26718JK01a\tpost\t?#%s\n' "$SSHA" > "$META/sub/.be/refs"
printf '26718JK01b\tpost\t?#%s\n' "$ASHA" > "$META/alt/.be/refs"

# COMMIT the de-jure gitlink pin `sub@SSHA` into META's baseline tree: put the
# .gitmodules blob, seed the gitlink-bump wtlog row (jab has no CLI spelling for
# a manual pin — the test/sub harness idiom), then post so fold-decide lands the
# 160000 entry.  `alt` is DECLARED but never pinned -> stays counter-less.
cat > "$WORK/.pinrow.js" <<'EOF'
const ulog = require(process.argv[2] + "/shared/ulog.js");
ulog.append(process.argv[4], [{ verb: "put",
  uri: URI.make(undefined, undefined, process.argv[3], undefined, process.argv[5]) }]);
EOF
( cd "$META" && "$BE" put .gitmodules ) >/dev/null 2>&1 || _fail "META put .gitmodules"
"$JABC" "$WORK/.pinrow.js" "$BEDIR" "sub" "$META/.be/wtlog" "$SSHA" >/dev/null 2>&1 \
    || _fail "seed gitlink pin row"
( cd "$META" && "$BE" post 'mount sub gitlink' ) >/dev/null 2>&1 || _fail "META post"
MSHA=$(grep -o '[0-9a-f]\{40\}' "$META/.be/wtlog" | tail -1)   # META tip (a META sha)
[ -n "$MSHA" ] || _fail "META tip capture"
grep -qE "put[[:space:]]+sub#[0-9a-f]{40}" "$META/.be/wtlog" \
    || _fail "gitlink pin not committed: $(cat "$META/.be/wtlog")"

# ADVANCE the mount PAST its committed pin (the live //WHY shape: be moved on,
# the parent's de-jure pin did not).  PINW tracks the PIN (SSHA), so it must read
# 0/0 vs the pin — NOT `-1` vs sub's now-newer live tip.  A fix that mistakenly
# kept reading the mount's OWN tip would render a `-1` here.
( cd "$META/sub" && printf 's2\n' >> s.txt && "$BE" post 'sub two' ) \
    >/dev/null 2>&1 || _fail "advance sub"
S2SHA=$(_sha40 "$META/sub/.be/wtlog" 2)
[ -n "$S2SHA" ] && [ "$S2SHA" != "$SSHA" ] || _fail "sub did not advance past the pin"
printf '26718JK01a\tpost\t?#%s\n' "$S2SHA" > "$META/sub/.be/refs"

# --- the tracker worktrees (hand-written .be redirects, the test/work/view idiom)
# PINW tracks the slashLESS gitlink pin `///sub#SSHA` -> hangs under META, ahbeh
# vs META's committed pin of sub (SSHA) -> IN SYNC (0/0), counter-less.
mkdir -p "$META/work/PINW"
printf '26718JK02a\tget\tfile:%s/sub/.be/?\n26718JK02b\tget\t///sub#%s\n' \
    "$META" "$SSHA" > "$META/work/PINW/.be"
# ALTW tracks the slashLESS `///alt#ASHA`, but META carries NO gitlink pin of
# alt -> no counts (like a repo row's unpinned mount), counter-less.
mkdir -p "$META/work/ALTW"
printf '26718JK02c\tget\tfile:%s/alt/.be/?\n26718JK02d\tget\t///alt#%s\n' \
    "$META" "$ASHA" > "$META/work/ALTW/.be"

# --- render the forest (plain: chrome-free, ahbeh as text `+N`/`-N`) ---------
( cd "$META" && "$BE" work --plain ) > "$WORK/forest.out" 2>"$WORK/forest.err" \
    || _fail "jab work failed: $(cat "$WORK/forest.err")"

# Block-1 row extractor for a wt KEY (the plain tracker row).
_row() { grep -F "//$1 " "$WORK/forest.out" | head -1; }

# WORK-007: both trackers are slashLESS pins -> they hang under META (root-level
# dotted `└┄┄`/`├┄┄`), NOT under the sub/alt subtrees (no leading `│`/indent).
_row PINW | grep -qE '^[├└]┄┄ //PINW' \
    || _fail "PINW not a META-level pin tracker: $(_row PINW)"
_row ALTW | grep -qE '^[├└]┄┄ //ALTW' \
    || _fail "ALTW not a META-level pin tracker: $(_row ALTW)"

# WORK-012 CORE: a pin-form tracker reads vs the PARENT's gitlink PIN, never the
# parent's own tip.  PINW is in sync with the pin (SSHA) -> NO ahbeh counter; the
# pre-fix code compared SSHA vs META's tip (a cross-repo walk) and rendered a
# `+N`/`-N` counter (the `[+99][-1]` garbage).  ALTW's mount is unpinned -> no
# counts at all.  A counter shows as a `+`/`-` digit before the DDMMM date core.
_row PINW | grep -qE '[-+][0-9]' \
    && _fail "WORK-012: PINW carries a counter — read vs parent tip, not the gitlink pin: $(_row PINW)"
_row ALTW | grep -qE '[-+][0-9]' \
    && _fail "WORK-012: ALTW (unpinned mount) carries a counter — expected none: $(_row ALTW)"

# Both rows still render (the fix must not drop them from block 1).
_row PINW | grep -q "$(printf '%s' "$SSHA" | cut -c1-8)" \
    || _fail "PINW row lost its #hashlet"
_row ALTW | grep -q "$(printf '%s' "$ASHA" | cut -c1-8)" \
    || _fail "ALTW row lost its #hashlet"

echo "PASS [work/$NAME]"
