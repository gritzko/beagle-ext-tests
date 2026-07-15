#!/bin/sh
# test/done/close — BE-040: the `done` mutation verb closes a ticket from the
# CLI: `jab done KEY` flips the page header to `#   KEY [DONE]: title` (the
# three todo/mark-done.sh forms: `KEY [MARK]:` replace, `KEY: [MARK] ` replace,
# `KEY: title` insert), delists the key's bullet (`^\s*-\s+\[?KEY\b`) from BOTH
# the topic README and the board README, and emits ONE confirmation hunk row
# per key (key + title).  Footer refdefs and mid-bullet mentions stay; an
# already-[DONE]/[WONTFIX] page gets one "already closed" row and ZERO edits;
# an unknown key is ONE uniform `done: KEY: TODONONE` line (BE-003 spirit);
# an odd header is reported and skipped, no edit.  File edits ONLY — the verb
# never commits/posts.  The ticket tree is a FIXTURE under $TMP (never the live
# journal).  URI-016: be.todoRoot() IS `projectRoot()+"/todo"` — no env var
# names it (the project root is DETECTED by the `.be` climb), so the fixture
# lives INSIDE the worktree we run from ($WT/todo/).
# Registered by the be/test glob as be-js-done-close — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/done/close
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "done/close: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "done/close: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=close
WORK="$TMP/$$/done/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink (bareword `jab done`
# resolves the extension via jab's upward be/-scan from the worktree cwd).
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [done/$NAME] $*" >&2; exit 1; }

# --- the FIXTURE ticket tree -------------------------------------------------
# FIX-001 thin, form 1 (`KEY [MARK]:`); FIX-002 fat, form 2 (`KEY: [MARK] `);
# FIX-003 already [DONE]; FIX-004 thin, form 3 (`KEY: title`); FIX-005 odd
# header; FIX-0011 a prefix-key neighbour whose bullet must survive FIX-001;
# FIX-006 the wild two-mark `[OPEN] [MED]` run (RULING 2026-07-10: ONE mark is
# canonical, the leading run must still collapse to ONE `[DONE]`); FIX-007 `[OPEN]`.
#
# URI-016: the tree sits in the worktree we run from — `todoRoot()` is
# `projectRoot()+"/todo"` and $WT's own `.be/` is the topmost anchor below the
# ctest-set $BE_ROOT, so projectRoot() == $WT.
WT="$WORK/wt"; mkdir -p "$WT/.be"
META="$WT"
mkdir -p "$META/todo/FIX/FIX-002"
cat > "$META/todo/README.mkd" <<'EOF'
#   Fixture ticket board

 -  [FIX] the fixture topic
    -  [FIX-001] thin sample — closing goes sideways
    -  FIX-002 fat sample (bare-key bullet form)
    -  [FIX-003] pre-closed sample
    -  [FIX-0011] prefix-key neighbour must stay
 -  a mid-bullet mention of FIX-001 must stay

[FIX-001]: FIX/FIX-001.mkd "footer refdef must stay"
EOF
cat > "$META/todo/FIX/README.mkd" <<'EOF'
#   FIX — fixture topic

 -  [FIX-001] thin sample — closing goes sideways
 -  FIX-002 fat sample (bare-key bullet form)
 -  [FIX-003] pre-closed sample
 -  [FIX-004] bare-title sample
 -  [FIX-005] odd-header sample
 -  [FIX-006] double-mark sample
 -  [FIX-007] open-mark sample
 -  [FIX-0011] prefix-key neighbour must stay
 -  a mid-bullet mention of FIX-001 must stay

[FIX-001]: FIX-001.mkd "footer refdef must stay"
[FIX-002]: FIX-002/README.mkd "fat refdef stays too"
EOF
cat > "$META/todo/FIX/FIX-001.mkd" <<'EOF'
#   FIX-001 [MED]: thin sample — closing goes sideways

Body line mentioning FIX-001 must survive the header flip untouched.

##  Outcome
 -  (open)
EOF
cat > "$META/todo/FIX/FIX-002/README.mkd" <<'EOF'
#   FIX-002: [HIGH] fat sample (dir layout)

A fat ticket lives at todo/FIX/FIX-002/README.mkd.
EOF
cat > "$META/todo/FIX/FIX-003.mkd" <<'EOF'
#   FIX-003 [DONE]: pre-closed sample
EOF
cat > "$META/todo/FIX/FIX-004.mkd" <<'EOF'
#   FIX-004: bare-title sample
EOF
cat > "$META/todo/FIX/FIX-005.mkd" <<'EOF'
##  FIX-005 odd header page (wrong form — report, skip, no edit)
EOF
cat > "$META/todo/FIX/FIX-006.mkd" <<'EOF'
#   FIX-006 [OPEN] [MED]: double-mark sample (redundant wild form)
EOF
cat > "$META/todo/FIX/FIX-007.mkd" <<'EOF'
#   FIX-007 [OPEN]: open-mark sample
EOF
cat > "$META/todo/FIX/FIX-0011.mkd" <<'EOF'
#   FIX-0011: prefix-key neighbour
EOF
# --- seed the worktree the loop runs from ------------------------------------
cd "$WT"
printf 'seed\n' > a.txt
"$BE" post 'seed commit' >/dev/null 2>&1 || _fail "seed post"

# --- 1. thin close, form 1: header flip + delist from BOTH READMEs -----------
"$BE" done FIX-001 --plain > "$WORK/one.out" 2>"$WORK/one.err" \
    || _fail "jab done FIX-001 failed: $(cat "$WORK/one.err")"
[ "$(head -n 1 "$META/todo/FIX/FIX-001.mkd")" = \
  '#   FIX-001 [DONE]: thin sample — closing goes sideways' ] \
    || _fail "form-1 header not flipped: $(head -n 1 "$META/todo/FIX/FIX-001.mkd")"
# the page BODY (all but line 1) survives byte-for-byte
tail -n +2 "$META/todo/FIX/FIX-001.mkd" > "$WORK/body.got"
cat > "$WORK/body.want" <<'EOF'

Body line mentioning FIX-001 must survive the header flip untouched.

##  Outcome
 -  (open)
EOF
cmp -s "$WORK/body.want" "$WORK/body.got" || _fail "FIX-001 body edited beyond the header"
# bullet delisted from the topic README AND the board README
grep -qE '^[[:space:]]*-[[:space:]]+\[?FIX-001\b' "$META/todo/FIX/README.mkd" \
    && _fail "topic README still lists the FIX-001 bullet"
grep -qE '^[[:space:]]*-[[:space:]]+\[?FIX-001\b' "$META/todo/README.mkd" \
    && _fail "board README still lists the FIX-001 bullet"
# footer refdefs, mid-bullet mentions, and the prefix-key neighbour ALL stay
grep -q '^\[FIX-001\]: FIX-001.mkd' "$META/todo/FIX/README.mkd" || _fail "topic refdef lost"
grep -q '^\[FIX-001\]: FIX/FIX-001.mkd' "$META/todo/README.mkd" || _fail "board refdef lost"
grep -q 'mid-bullet mention of FIX-001 must stay' "$META/todo/FIX/README.mkd" \
    || _fail "topic mid-bullet mention lost"
grep -q 'mid-bullet mention of FIX-001 must stay' "$META/todo/README.mkd" \
    || _fail "board mid-bullet mention lost"
grep -q 'FIX-0011' "$META/todo/FIX/README.mkd" || _fail "prefix-key FIX-0011 bullet lost (topic)"
grep -q 'FIX-0011' "$META/todo/README.mkd" || _fail "prefix-key FIX-0011 bullet lost (board)"
# ONE confirmation row: key + title
grep -q 'done FIX-001 \[DONE\]: thin sample' "$WORK/one.out" \
    || _fail "no confirmation row for FIX-001: $(cat "$WORK/one.out")"
[ "$(grep -c 'done FIX-001' "$WORK/one.out")" = 1 ] || _fail "not exactly ONE FIX-001 row"

# --- 2. multi-key: fat form 2 + thin form 3, one row per key ------------------
"$BE" done FIX-002 FIX-004 --plain > "$WORK/multi.out" 2>&1 || _fail "jab done FIX-002 FIX-004 failed"
[ "$(head -n 1 "$META/todo/FIX/FIX-002/README.mkd")" = \
  '#   FIX-002: [DONE] fat sample (dir layout)' ] \
    || _fail "form-2 header not flipped: $(head -n 1 "$META/todo/FIX/FIX-002/README.mkd")"
[ "$(head -n 1 "$META/todo/FIX/FIX-004.mkd")" = \
  '#   FIX-004 [DONE]: bare-title sample' ] \
    || _fail "form-3 header not flipped: $(head -n 1 "$META/todo/FIX/FIX-004.mkd")"
grep -qE '^[[:space:]]*-[[:space:]]+\[?FIX-002\b' "$META/todo/FIX/README.mkd" \
    && _fail "topic README still lists the FIX-002 bullet"
grep -qE '^[[:space:]]*-[[:space:]]+FIX-002\b' "$META/todo/README.mkd" \
    && _fail "board README still lists the FIX-002 bullet"
grep -q '^\[FIX-002\]: FIX-002/README.mkd' "$META/todo/FIX/README.mkd" || _fail "FIX-002 refdef lost"
grep -q 'done FIX-002' "$WORK/multi.out" || _fail "no confirmation row for FIX-002"
grep -q 'done FIX-004' "$WORK/multi.out" || _fail "no confirmation row for FIX-004"
[ "$(grep -c '^........done FIX-' "$WORK/multi.out")" = 2 ] \
    || _fail "multi-key must emit exactly one row per key: $(cat "$WORK/multi.out")"

# --- 3. already closed: one row, ZERO edits -----------------------------------
cp "$META/todo/FIX/FIX-003.mkd" "$WORK/fix3.before"
cp "$META/todo/README.mkd" "$WORK/board.before"
cp "$META/todo/FIX/README.mkd" "$WORK/topic.before"
"$BE" done FIX-003 --plain > "$WORK/closed.out" 2>&1 || _fail "jab done FIX-003 (closed) failed"
grep -q 'already closed' "$WORK/closed.out" || _fail "no 'already closed' row for FIX-003"
cmp -s "$WORK/fix3.before" "$META/todo/FIX/FIX-003.mkd" || _fail "already-closed page edited"
cmp -s "$WORK/board.before" "$META/todo/README.mkd" || _fail "board README edited on already-closed"
cmp -s "$WORK/topic.before" "$META/todo/FIX/README.mkd" || _fail "topic README edited on already-closed"

# --- 3b. idempotent: a second `done FIX-001` is an already-closed no-op -------
cp "$META/todo/FIX/FIX-001.mkd" "$WORK/fix1.before"
"$BE" done FIX-001 --plain > "$WORK/again.out" 2>&1 || _fail "second jab done FIX-001 failed"
grep -q 'already closed' "$WORK/again.out" || _fail "second done FIX-001 lacks 'already closed'"
cmp -s "$WORK/fix1.before" "$META/todo/FIX/FIX-001.mkd" || _fail "second done FIX-001 edited the page"

# --- 4. unknown key: ONE uniform TODONONE line, non-zero exit ------------------
if "$BE" done FIX-999 --plain > "$WORK/miss.out" 2>&1; then _fail "done FIX-999 exited 0"; fi
grep -q 'done: FIX-999: TODONONE' "$WORK/miss.out" || _fail "miss lacks the uniform TODONONE line"
[ "$(grep -c 'done: FIX-999: TODONONE' "$WORK/miss.out")" = 1 ] || _fail "TODONONE line not unique"

# --- 4b. a non-key arg is the same uniform miss --------------------------------
if "$BE" done notakey --plain > "$WORK/shape.out" 2>&1; then _fail "done notakey exited 0"; fi
grep -q 'done: notakey: TODONONE' "$WORK/shape.out" || _fail "non-key arg lacks the TODONONE line"

# --- 5. odd header: a VISIBLE row (stdout, not just stderr), skip, NO edit ----
# RULING 2026-07-10: the pager shows only hunk rows — a rowless skip answered
# `:done KEY` with "no hunks", so the odd-header report must BE a row.
cp "$META/todo/FIX/FIX-005.mkd" "$WORK/fix5.before"
"$BE" done FIX-005 --plain > "$WORK/odd.out" 2>"$WORK/odd.err" \
    || _fail "jab done FIX-005 (odd) failed: $(cat "$WORK/odd.err")"
grep -q 'done FIX-005' "$WORK/odd.out" || _fail "odd header lacks a visible stdout row: $(cat "$WORK/odd.out")"
grep -q 'odd header' "$WORK/odd.out" || _fail "odd-header row does not say so: $(cat "$WORK/odd.out")"
cmp -s "$WORK/fix5.before" "$META/todo/FIX/FIX-005.mkd" || _fail "odd-header page edited"

# --- 6. two-mark `[OPEN] [MED]` run collapses to ONE `[DONE]` ------------------
"$BE" done FIX-006 --plain > "$WORK/two.out" 2>&1 || _fail "jab done FIX-006 (two-mark) failed"
[ "$(head -n 1 "$META/todo/FIX/FIX-006.mkd")" = \
  '#   FIX-006 [DONE]: double-mark sample (redundant wild form)' ] \
    || _fail "two-mark header not collapsed: $(head -n 1 "$META/todo/FIX/FIX-006.mkd")"
grep -q 'done FIX-006 \[DONE\]: double-mark sample' "$WORK/two.out" \
    || _fail "no confirmation row for FIX-006: $(cat "$WORK/two.out")"
grep -qE '^[[:space:]]*-[[:space:]]+\[?FIX-006\b' "$META/todo/FIX/README.mkd" \
    && _fail "topic README still lists the FIX-006 bullet"

# --- 6b. lone `[OPEN]` mark flips like any priority mark -----------------------
"$BE" done FIX-007 --plain > "$WORK/open.out" 2>&1 || _fail "jab done FIX-007 (open-mark) failed"
[ "$(head -n 1 "$META/todo/FIX/FIX-007.mkd")" = \
  '#   FIX-007 [DONE]: open-mark sample' ] \
    || _fail "[OPEN] header not flipped: $(head -n 1 "$META/todo/FIX/FIX-007.mkd")"
grep -q 'done FIX-007 \[DONE\]: open-mark sample' "$WORK/open.out" \
    || _fail "no confirmation row for FIX-007: $(cat "$WORK/open.out")"

echo "PASS [done/$NAME]"
