#!/bin/sh
# test/todo/click — TODO-004: the meta-pair CLICK round-trips, driven through
# the REAL UI path.  Not a tlv probe and not a hand-built Pager: this forks a
# pty, `exec`s the real `jab todo …` in it (isatty(1) → the universal bro
# pager, JAB-030), feeds a real SGR left-press report at the cell the meta
# pair paints on, and asserts the PAINTED FRAME flips to the answer the spell
# names.  The pager stays arg-blind throughout — it drives the O spell, and
# the `todo` VERB resolves the arg (BRO-025).
#
# The ruling this pins (2026-08-03): a click REPLACES that key's filter and
# leaves the REST of the arg line alone, because the spell carries the WHOLE
# arg line (never a `todo(key,value)` call).  The painted BANNER is the address
# bar, so the round-trips read straight off the frame:
#   `todo CLK Now:*`       click OPEN -> `todo CLK Now:OPEN`
#     back, then           click DONE -> `todo CLK Now:DONE`  (REPLACED — not
#                                        two filters, not a fresh line)
#   `todo CLK Now:* Sev:*` click HIGH -> `todo CLK Now:* Sev:HIGH`
#   ticket page CLK-001    click Now: -> `todo CLK Now:*`
#   ticket page CLK-001    click OPEN -> `todo CLK Now:OPEN`
#
# TODO-005 adds the BUTTON leg.  `work/CLK-001` is a real worktree with one
# modified tracked file AND a mounted sub carrying another, so its file frame
# paints `[ i ~2 ...]` — the counts are the WHOLE tree's, because bare put and
# bare delete both descend every mount (SUBS-044).  A click on that count drives
# the MUTATION spell `//CLK-001/: put`; the row repaints with the class greyed
# (staged) and the files are staged in the wt's AND the sub's own wtlogs.
# `work/CLK-002` is genuinely DIVERGED from what it tracks (its own commit vs a
# commit in CLK-001), so its commit frame paints the `A⇄B` patch button and a
# click there runs `patch` for real.  Every button is asserted at the SGR level:
# its exact truecolor fg across the face, and no background anywhere.
# Registered by the be/test glob as be-js-todo-click — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/todo/click
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "todo/click: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "todo/click: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/views/bro/pager.js" ] || { echo "todo/click: SKIP — no pager.js" >&2; exit 0; }
[ -f "$BEDIR/shared/metaidx.js" ] || { echo "todo/click: SKIP — no metaidx.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

# The driver is a controlling-terminal harness (the test/bro/universal model).
command -v python3 >/dev/null 2>&1 || { echo "todo/click: SKIP — no python3" >&2; exit 0; }
python3 -c "import pty,select,fcntl,termios" 2>/dev/null \
    || { echo "todo/click: SKIP — no pty module" >&2; exit 0; }

: "${TMP:=/tmp}"; export TMP
NAME=click
WORK="$TMP/$$/todo/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [todo/$NAME] $*" >&2; exit 1; }

# SKIP if the jab build lacks the tty binding (pre-JS-053: no pager at all).
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.size === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo no)
[ "$HAS" = "yes" ] || { echo "todo/click: SKIP — jab has no tty binding" >&2; exit 0; }

# --- the fixture (the todo/meta model, kept SHORT so no row soft-wraps) -----
# CLK-001's page must paint `Now: OPEN` on a KNOWN cell: the header is file
# line 1 and the pair block starts at line 2, and the pager paints the banner
# on screen row 1 — so `Now:` is row 3, columns 1-4, and its value columns 6-9.
# In a LISTING the rows are topic+number ordered (time-sort is postponed), so
# CLK-001/2/3 land on screen rows 2/3/4 and every inline value opens at column
# 10 (`CLK-001` 1-7, ` ` 8, `[` 9).
WT="$WORK/wt"; mkdir -p "$WT/.be" "$WT/todo/CLK"
cat > "$WT/todo/CLK/CLK-001.mkd" <<'EOF'
#   CLK-001: alpha
Now: OPEN
Sev: HIGH
EOF
cat > "$WT/todo/CLK/CLK-002.mkd" <<'EOF'
#   CLK-002: beta
Now: OPEN
Sev: LOW
EOF
# the ONLY closed ticket: the witness.  The implicit `Now:` default hides it,
# `Now:*` shows it (so a DONE value is on screen to click), and `Now:DONE` is
# what the click must leave behind.
cat > "$WT/todo/CLK/CLK-003.mkd" <<'EOF'
#   CLK-003: gamma
Now: DONE
EOF
# TODO-005 [go]: a wt-LESS ticket carrying `Rep:` (the repo it relates to) gets
# the mint button; CLK-002 carries none, so it keeps the plain dotted leader.
cat > "$WT/todo/CLK/CLK-004.mkd" <<'EOF'
#   CLK-004: delta
Now: OPEN
Rep: ///be
EOF

cd "$WT"
printf 'seed\n' > a.txt
"$BE" post 'seed commit' >/dev/null 2>&1 || _fail "seed post"

# TODO-005: a ticket-named WORKTREE under work/ makes CLK-001's board row grow
# the two BUTTON FRAMES, and one modified tracked file inside it lights the
# `~1` stage button — the cell scenario 4 clicks.
# the clone resolves the store's TRUNK ref ([/wiki/Store]: branches are ref
# rows), which a bare `post` does not write — plant it at the seed commit.
SEED=$(grep -o '[0-9a-f]\{40\}' "$WT/.be/wtlog" | sed -n 1p)
[ -n "$SEED" ] || _fail "seed sha capture"
printf '26718JF48j\tpost\t?#%s\n' "$SEED" > "$WT/.be/refs"
mkdir -p "$WT/work/CLK-001"
( cd "$WT/work/CLK-001" && "$BE" get "file:$WT/.be?" ) >/dev/null 2>&1 \
    || _fail "CLK-001 worktree clone"
C0=$SEED

# CLK-001 commits c1 (so CLK-002 can be BEHIND it), then goes dirty: one
# modified tracked file at the top and one inside a MOUNTED sub, so the frame's
# changed count can only read 2 if the sub folded in.
( cd "$WT/work/CLK-001" && printf 'c1\n' >> a.txt && "$BE" post 'c1' ) \
    >/dev/null 2>&1 || _fail "CLK-001 c1"
mkdir -p "$WT/work/CLK-001/lib"
cat > "$WT/work/CLK-001/.gitmodules" <<'EOF'
[submodule "lib"]
	path = lib
	url = git@example.invalid:nowhere/lib.git
EOF
( cd "$WT/work/CLK-001/lib" && mkdir -p .be && printf 'L\n' > b.txt \
  && "$BE" post 'lib base' ) >/dev/null 2>&1 || _fail "CLK-001 lib seed"
printf 'edited in the wt\n' >> "$WT/work/CLK-001/a.txt"

# CLK-002: cloned at c0, re-pointed at the CLK-001 WORKTREE (a uriTrack, the
# common `work/` shape), then given its OWN commit — cur and track have both
# moved, which is real divergence.  attachedBranch reads the recentmost GET row,
# so the hand-written track row survives the post.
mkdir -p "$WT/work/CLK-002"
( cd "$WT/work/CLK-002" && "$BE" get "file:$WT/.be?" ) >/dev/null 2>&1 \
    || _fail "CLK-002 worktree clone"
printf '26718JG001\tget\tfile:%s/.be/?\n26718JG002\tget\t//CLK-001/#%s\n' \
    "$WT" "$C0" > "$WT/work/CLK-002/.be"
( cd "$WT/work/CLK-002" && printf 'c2\n' >> a.txt && "$BE" post 'c2' ) \
    >/dev/null 2>&1 || _fail "CLK-002 c2"

"$BE" todo CLK --plain >/dev/null 2>&1 || _fail "the topic list does not render"

# --- the SUB-FOLD witness (a render diff, no click) -------------------------
# The changed count with the sub CLEAN, then with one sub file dirtied: the only
# thing that moved is inside the mount, so the count must move with it.
_chg() { ( cd "$WT" && "$BE" todo CLK --color ) 2>/dev/null \
         | sed -n "/$1/p" | sed 's/\x1b\[[0-9;]*m//g' \
         | sed -n 's/.*\[ i \(..\).*/\1/p'; }
BEFORE=$(_chg CLK-001)
printf 'dirtied in the sub\n' >> "$WT/work/CLK-001/lib/b.txt"
AFTER=$(_chg CLK-001)
[ "$BEFORE" = "~1" ] || _fail "sub-fold: changed count without the sub reads '$BEFORE', want '~1'"
[ "$AFTER" = "~2" ] || _fail "sub-fold: a dirty MOUNT must fold in — reads '$AFTER', want '~2'"
echo "     ok   sub-fold-counts   ($BEFORE -> $AFTER when a mounted sub goes dirty)"
# the store must answer before the pty leg (a first sweep inside the pager
# would still work, but a failure there would read as a click failure).
"$BE" todo --plain >/dev/null 2>&1 || _fail "the board does not render at all"

# the `~1` click stages inside the wt, so the wt's own status must answer first
# (a failure there would read as a click failure).
( cd "$WT/work/CLK-001" && "$BE" status --plain ) >/dev/null 2>&1 \
    || _fail "the wt does not classify at all"

python3 "$_CASE/click.py" "$JABC" "$WT" >"$WORK/out" 2>"$WORK/err" || {
    echo "--- stderr ---"; cat "$WORK/err"
    echo "--- out ---";    cat "$WORK/out"; _fail "pty click checks failed"; }
grep -q '^DONE' "$WORK/out" || { cat "$WORK/out"; _fail "the pty driver did not finish"; }
sed 's/^/     /' "$WORK/out"

echo "PASS [todo/$NAME]"
