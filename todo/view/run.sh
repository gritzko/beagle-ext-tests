#!/bin/sh
# test/todo/view — BE-038: the `todo` view verb browses the ticket board.
# Shape-routed: bare `todo` = the board (topics + one-liner titles), `todo GET`
# = one topic's list, `todo GET-001` = the ticket page (thin .mkd or fat
# KEY/README.mkd), a miss = ONE uniform `todo: <arg>: TODONONE` line.
# HEADER-GREP (ruling 2026-07-10): the ticket's own `#   KEY [MARK]: title`
# line is the truth — [DONE]/[WONTFIX] close, [CRIT]/[HIGH]/[LOW] order the
# list; topic READMEs are stale-able landing pages, never an index.  List
# rows + in-page ticket keys carry hidden `U` spell targets (`todo <KEY>`) so
# the pager's _uriAt click re-enters the view (asserted over --tlv, check.js).
# The ticket tree is a FIXTURE under $TMP (never the live journal), reached
# via $TODO_ROOT (be.todoRoot()'s first probe).  Registered by the be/test
# glob as be-js-todo-view — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/todo/view
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "todo/view: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "todo/view: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=view
WORK="$TMP/$$/todo/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the `be -> <be/>` shard symlink (bareword `jab todo`
# resolves the extension via jab's upward be/-scan from the worktree cwd).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [todo/$NAME] $*" >&2; exit 1; }

# --- the FIXTURE ticket tree (board / topic / thin / fat / second topic) ----
# GET has a curated README (open = GET-001, GET-002); GET-003 is CLOSED: its
# file remains, its bullet is delisted, only a footer refdef still names it.
# PUT has NO README → the open filter falls back to all files + a visible note.
META="$WORK/meta"
mkdir -p "$META/todo/GET/GET-002" "$META/todo/PUT" "$META/todo/done" "$META/wiki"
cat > "$META/todo/README.mkd" <<'EOF'
#   Active ticket board

Fixture board page (the view scans topic DIRS, not this page).
EOF
# The topic README is a landing page and DELIBERATELY STALE (lists closed
# GET-003, omits open GET-002/GET-004) — header-grep must ignore it entirely.
cat > "$META/todo/GET/README.mkd" <<'EOF'
#   GET — fixture topic (stale landing page, never an index)

 -  [GET-001] thin sample
 -  [GET-003] long closed, still listed here — must NOT resurrect
EOF
cat > "$META/todo/GET/GET-001.mkd" <<'EOF'
#   GET-001 [HIGH]: thin sample ticket — checkout goes sideways

Body mentions the sibling GET-002 so its key must become a click target.

##  Input
 -  see [GET-002] for the fat twin.
 -  see [W] for the wiki page.

[W]: ../../wiki/Sample.mkd "a wiki page reflink"
EOF
cat > "$META/todo/GET/GET-002/README.mkd" <<'EOF'
#   GET-002: fat sample ticket (dir layout)

A fat ticket lives at todo/GET/GET-002/README.mkd.
EOF
cat > "$META/todo/GET/GET-003.mkd" <<'EOF'
#   GET-003 [WONTFIX]: closed sample ticket (header mark, README-listed)
EOF
cat > "$META/todo/GET/GET-004.mkd" <<'EOF'
#   GET-004 [CRIT]: critical sample — must sort FIRST in the topic
EOF
cat > "$META/todo/GET/GET-005.mkd" <<'EOF'
#   GET-005 [LOW]: low-prio sample — must sort LAST in the topic
EOF
# the mark also parses AFTER the colon (`KEY: [MARK] …` — the ABC board form)
cat > "$META/todo/GET/GET-006.mkd" <<'EOF'
#   GET-006: [DONE] landed sample — an after-colon DONE mark hides it too
EOF
cat > "$META/todo/PUT/PUT-001.mkd" <<'EOF'
#   PUT-001: second-topic sample
EOF
cat > "$META/wiki/Sample.mkd" <<'EOF'
#   Sample wiki page

Wiki body.
EOF
# a closed ticket parked in done/ must NOT appear on the board
cat > "$META/todo/done/GET-000.mkd" <<'EOF'
#   GET-000: closed sample (must not list)
EOF
export TODO_ROOT="$META"

# --- a minimal seeded worktree to run the loop from ------------------------
WT="$WORK/wt"; mkdir -p "$WT/.be"
cd "$WT"
printf 'seed\n' > a.txt
"$BE" post 'seed commit' >/dev/null 2>&1 || _fail "seed post"

# --- 1. bare `todo`: the board — header marks decide, READMEs ignored -------
"$BE" todo --plain > "$WORK/board.out" 2>"$WORK/board.err" || _fail "jab todo failed: $(cat "$WORK/board.err")"
grep -q 'GET-001 \[HIGH\]: thin sample ticket' "$WORK/board.out" || _fail "board misses GET-001 title"
grep -q 'GET-002: fat sample ticket'           "$WORK/board.out" || _fail "board misses fat GET-002 (stale README omits it)"
grep -q 'GET-004 \[CRIT\]'                     "$WORK/board.out" || _fail "board misses GET-004 (stale README omits it)"
grep -q 'PUT-001: second-topic sample'         "$WORK/board.out" || _fail "board misses PUT-001 (no README at all)"
grep -q 'GET-000' "$WORK/board.out" && _fail "board lists done/ ticket GET-000"
# closed BY HEADER MARK — the stale README still listing GET-003 is IGNORED
grep -q 'GET-003' "$WORK/board.out" && _fail "board resurrects [WONTFIX] GET-003 (stale README obeyed?)"
grep -q 'GET-006' "$WORK/board.out" && _fail "board lists [DONE] GET-006"

# --- 1b. priority order within a topic: CRIT, HIGH, unmarked, LOW -----------
for k in GET-004 GET-001 GET-002 GET-005; do grep -n "^  $k" "$WORK/board.out" | head -1 | cut -d: -f1; done > "$WORK/ord.out"
sort -nc "$WORK/ord.out" 2>/dev/null || _fail "board priority order wrong (want CRIT,HIGH,unmarked,LOW): $(cat "$WORK/ord.out")"
[ "$(wc -l < "$WORK/ord.out")" = 4 ] || _fail "board misses a GET row for the order check"

# --- 2. `todo GET`: one topic, open only; `todo PUT`: README-less topic -----
"$BE" todo GET --plain > "$WORK/topic.out" 2>&1 || _fail "jab todo GET failed"
grep -q 'GET-001' "$WORK/topic.out" || _fail "topic misses GET-001"
grep -q 'GET-002' "$WORK/topic.out" || _fail "topic misses GET-002"
grep -q 'GET-003' "$WORK/topic.out" && _fail "topic GET resurrects [WONTFIX] GET-003"
grep -q 'PUT-001' "$WORK/topic.out" && _fail "topic GET lists PUT-001"
"$BE" todo PUT --plain > "$WORK/topicput.out" 2>&1 || _fail "jab todo PUT failed"
grep -q 'PUT-001' "$WORK/topicput.out" || _fail "topic PUT misses PUT-001"
grep -q 'no open-ticket list' "$WORK/topicput.out" && _fail "README-fallback note survived the header-grep rewrite"

# --- 2b. direct addressing ignores the open filter --------------------------
"$BE" todo GET-003 --plain > "$WORK/closed.out" 2>&1 || _fail "jab todo GET-003 (closed) failed"
grep -q 'closed sample ticket' "$WORK/closed.out" || _fail "closed GET-003 page did not render"

# --- 2c. an ALL-CLOSED topic still answers `todo TOPIC` with a visible note -
mkdir -p "$META/todo/NIX"
printf '#   NIX-001 [DONE]: the only ticket, closed\n' > "$META/todo/NIX/NIX-001.mkd"
"$BE" todo NIX --plain > "$WORK/nix.out" 2>&1 || _fail "jab todo NIX (all closed) failed"
grep -q 'no open tickets in todo/NIX/' "$WORK/nix.out" || _fail "all-closed topic lacks the empty note"
"$BE" todo --plain > "$WORK/board2.out" 2>&1 || _fail "jab todo (2) failed"
grep -q 'NIX' "$WORK/board2.out" && _fail "board lists the all-closed topic NIX"

# --- 3. thin ticket page -----------------------------------------------------
"$BE" todo GET-001 --plain > "$WORK/thin.out" 2>&1 || _fail "jab todo GET-001 failed"
grep -q 'thin sample ticket' "$WORK/thin.out" || _fail "thin page body missing"
grep -q 'fat twin' "$WORK/thin.out" || _fail "thin page body truncated"

# --- 4. fat ticket page (KEY/README.mkd) ------------------------------------
"$BE" todo GET-002 --plain > "$WORK/fat.out" 2>&1 || _fail "jab todo GET-002 failed"
grep -q 'fat ticket lives at' "$WORK/fat.out" || _fail "fat page body missing"

# --- 5. miss = ONE uniform TODONONE line, non-zero exit ---------------------
if "$BE" todo GET-999 --plain > "$WORK/miss.out" 2>&1; then _fail "todo GET-999 exited 0"; fi
grep -q 'todo: GET-999: TODONONE' "$WORK/miss.out" || _fail "miss lacks the uniform TODONONE line"

# --- 6. click targets: board rows + in-page keys carry U `todo <KEY>` -------
"$BE" todo --tlv > "$WORK/board.tlv" 2>/dev/null || _fail "jab todo --tlv failed"
[ -s "$WORK/board.tlv" ] || _fail "todo --tlv emitted ZERO bytes"
"$JABC" "$_CASE/check.js" "$WORK/board.tlv" board >"$WORK/check1.out" 2>&1 \
    || { cat "$WORK/check1.out" >&2; _fail "board U-target assertions failed"; }
"$BE" todo GET-001 --tlv > "$WORK/thin.tlv" 2>/dev/null || _fail "jab todo GET-001 --tlv failed"
"$JABC" "$_CASE/check.js" "$WORK/thin.tlv" page >"$WORK/check2.out" 2>&1 \
    || { cat "$WORK/check2.out" >&2; _fail "page U-target assertions failed"; }

echo "PASS [todo/$NAME]"
