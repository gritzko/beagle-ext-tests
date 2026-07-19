#!/bin/sh
# test/work/view — WORK-001: bare `work` renders the worktree FOREST in three
# tree hunks (main-tree-tracking / branch-tracking / remote-tracking; an empty
# hunk is ABSENT), Unicode box-drawing rails, every wt hung under what it
# TRACKS, ahead/behind counts vs the TRACKED ref.  WORK-004 row form:
# `//KEY ┄┄┄  [diff] [post]  [+N][-N]  <time5> #<hashlet8> <subject≤30>
# [done] [dont]` — [get] retired; the ahbeh counts ARE buttons (`[+N]` mints
# bare post, `[-N]` bare get); the rails+name column dotted-pads to KEYW=32 and
# the slots are fixed, so every column aligns view-wide (r2); plain chrome-free.
# [done]/[dont] move the wt into work/done/ (the r2 discard root, IGNORED by
# the view; bump on collision) and flip a ticket-named wt's page header to
# [DONE]/[DONT].  The FIXTURE forest: a
# project root (colocated store) with a mount vend/ext (2 commits, planted
# trunk+`feature` refs) and a NESTED mount vend/ext/deep, plus five work/ wts —
# TRK-5 (a real trunk clone, in sync), PIN-1 (tracks the vend/ext WORKTREE,
# behind 1), BR-2 (tracks branch `feature`, ahead 1), DET-3 (bare-hash
# detached), FOR-4 (a store OUTSIDE the project's stores).  work/junk (no .be)
# and work/README.mkd never list.  Registered as be-js-work-view (test glob).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/work/view
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "work/view: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "work/view: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=view
WORK="$TMP/$$/work/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the jsrc symlink (bareword `jab work` resolves via jab's
# upward jsrc/-scan from the fixture cwd).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [work/$NAME] $*" >&2; exit 1; }
_sha40() { grep -o '[0-9a-f]\{40\}' "$1" | sed -n "$2p"; }

# --- the FIXTURE project tree (real colocated stores, jab-posted commits) ----
META="$WORK/meta"
mkdir -p "$META/.be" "$META/vend/ext/.be" "$META/vend/ext/deep/.be" \
         "$META/todo/PIN" "$META/work/junk" "$WORK/foreign/.be"
cat > "$META/.gitmodules" <<'EOF'
[submodule "ext"]
	path = vend/ext
	url = git@github.com:nowhere/extproj.git
EOF
cat > "$META/vend/ext/.gitmodules" <<'EOF'
[submodule "deep"]
	path = deep
	url = git@github.com:nowhere/deepproj.git
EOF
mkdir -p "$META/todo/DET"
cat > "$META/todo/PIN/PIN-1.mkd" <<'EOF'
#   PIN-1: pin sample ticket
EOF
cat > "$META/todo/DET/DET-3.mkd" <<'EOF'
#   DET-3: detached sample ticket
EOF
printf 'fixture, not a worktree\n' > "$META/work/README.mkd"

# WORK-005: the age fade reads be.now - commit ts (real now at `work` time), so
# PIN the seed COMMIT ts via SOURCE_DATE_EPOCH — never mock now.  ext one is
# aged 8.5d (PIN-1 tracks SHA1 -> #888888), ext two 3.5d (TRK-5 -> #333333);
# root/deep/foreign stay fresh (DET-3/FOR-4 -> #000000).
NOWSEC=$(date +%s)
AGE8=$((NOWSEC - 8*86400 - 43200)); AGE3=$((NOWSEC - 3*86400 - 43200))
( cd "$META" && printf 'root\n' > R.txt && "$BE" post 'root commit' ) \
    >/dev/null 2>&1 || _fail "seed root post"
( cd "$META/vend/ext" && printf 'e1\n' > e.txt \
  && SOURCE_DATE_EPOCH=$AGE8 "$BE" post 'ext one' ) \
    >/dev/null 2>&1 || _fail "seed ext one"
( cd "$META/vend/ext" && printf 'e2\n' >> e.txt \
  && SOURCE_DATE_EPOCH=$AGE3 "$BE" post 'ext two' ) \
    >/dev/null 2>&1 || _fail "seed ext two"
( cd "$META/vend/ext/deep" && printf 'd1\n' > d.txt \
  && "$BE" post 'deep one with a very long subject line' ) \
    >/dev/null 2>&1 || _fail "seed deep one"
( cd "$WORK/foreign" && printf 'f1\n' > f.txt && "$BE" post 'foreign one' ) \
    >/dev/null 2>&1 || _fail "seed foreign one"

RSHA=$(_sha40 "$META/.be/wtlog" 1)
SHA1=$(_sha40 "$META/vend/ext/.be/wtlog" 1)          # ext one
SHA2=$(_sha40 "$META/vend/ext/.be/wtlog" 2)          # ext two
DSHA=$(_sha40 "$META/vend/ext/deep/.be/wtlog" 1)
FSHA=$(_sha40 "$WORK/foreign/.be/wtlog" 1)
[ -n "$RSHA" ] && [ -n "$SHA1" ] && [ -n "$SHA2" ] && [ -n "$DSHA" ] && [ -n "$FSHA" ] \
    || _fail "sha capture"

# Trunk + branch refs ([/wiki/Store]: branches are ref rows): ext trunk -> SHA2,
# `feature` pinned at SHA1; deep/foreign trunks at their tips (get needs a trunk).
printf '26718JF48j\tpost\t?#%s\n26718JF49f\tpost\t?#%s\n26718JF49g\tpost\t?feature#%s\n' \
    "$SHA1" "$SHA2" "$SHA1" > "$META/vend/ext/.be/refs"
printf '26718JF49h\tpost\t?#%s\n' "$DSHA" > "$META/vend/ext/deep/.be/refs"
printf '26718JF49i\tpost\t?#%s\n' "$FSHA" > "$WORK/foreign/.be/refs"

# --- the five work/ worktrees -----------------------------------------------
# TRK-5: a REAL trunk clone (row0 anchor + `get ?#<sha>`), in sync with trunk.
mkdir -p "$META/work/TRK-5"
( cd "$META/work/TRK-5" && "$BE" get "file:$META/vend/ext/.be?" ) \
    >/dev/null 2>&1 || _fail "TRK-5 clone"
grep -q "$SHA2" "$META/work/TRK-5/.be" || _fail "TRK-5 clone not at trunk"
# PIN-1: tracks the vend/ext WORKTREE (a URI-shaped track), based at SHA1.
mkdir -p "$META/work/PIN-1"
printf '26718JG001\tget\tfile:%s/vend/ext/.be/?\n26718JG002\tget\t///vend/ext#%s\n' \
    "$META" "$SHA1" > "$META/work/PIN-1/.be"
# BR-2: tracks branch `feature` (pinned at SHA1), based at SHA2 -> ahead 1.
mkdir -p "$META/work/BR-2"
printf '26718JG003\tget\tfile:%s/vend/ext/.be/?\n26718JG004\tget\t?feature#%s\n' \
    "$META" "$SHA2" > "$META/work/BR-2/.be"
# DET-3: DETACHED (the DIS-075 bare-hash record) off the deep store.
mkdir -p "$META/work/DET-3"
printf '26718JG005\tget\tfile:%s/vend/ext/deep/.be/?\n26718JG006\tget\t#%s\n' \
    "$META" "$DSHA" > "$META/work/DET-3/.be"
# FOR-4: anchored OUTSIDE the project's stores -> the remote hunk.
mkdir -p "$META/work/FOR-4"
printf '26718JG007\tget\tfile:%s/foreign/.be/?\n26718JG008\tget\t?#%s\n' \
    "$WORK" "$FSHA" > "$META/work/FOR-4/.be"

h() { printf '%s' "$1" | cut -c1-8; }

# --- 1. plain: the pinned forest (dates normalized, chrome-free) -------------
( cd "$META" && "$BE" work --plain ) > "$WORK/forest.out" 2>"$WORK/forest.err" \
    || _fail "jab work failed: $(cat "$WORK/forest.err")"
# Normalize the 5-char date core (today `HH:MM`, this-week `Dow15`, older
# `DDMon`) to DDMMM — WORK-005 ages ext two ~3.5d, so it renders the weekday form.
sed 's/[0-9][0-9]:[0-9][0-9]/DDMMM/g; s/[0-9][0-9][A-Z][a-z][a-z]/DDMMM/g; s/[A-Z][a-z][a-z][0-9][0-9]/DDMMM/g' \
    "$WORK/forest.out" > "$WORK/forest.norm"
# The plain edge prints each hunk's `work` banner + a trailing blank separator;
# store paths render home-abbreviated (the sketch's `file:~/...` form).
MTIL=$(printf '%s' "$META" | sed "s|^$HOME|~|")
WTIL=$(printf '%s' "$WORK" | sed "s|^$HOME|~|")
# Review 2026-07-18: mounts first (SOLID rails, .gitmodules order), then ALL
# tracker wts as ONE name-sorted run on DOTTED rails (`├┄┄`) — trackers never
# read as real subdirs; same characters in plain (structure, not styling).
# R2: the rails+name column pads to KEYW=32 with a dotted leader (` ┄┄┄`) so
# the shared ahbeh/time/hashlet/message columns align down the whole view;
# repo rows share the ahbeh column (empty here — post-seeded fixture subs
# carry no de-jure parent pin; the live fleet exercises the pin counts).
cat > "$WORK/forest.want" <<EOF
work
meta ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄         DDMMM #$(h "$RSHA") root commit
└── vend/ext ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄         DDMMM #$(h "$SHA2") ext two
    ├── deep ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄         DDMMM #$(h "$DSHA") deep one with a very long subject line
    ├┄┄ //PIN-1 ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄      -1 DDMMM #$(h "$SHA1") ext one
    └┄┄ //TRK-5 ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄         DDMMM #$(h "$SHA2") ext two

work
file:$MTIL/vend/ext/.be
└── feature
    └┄┄ //BR-2 ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄      +1 DDMMM #$(h "$SHA2") ext two
file:$MTIL/vend/ext/deep/.be
└┄┄ //DET-3 ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄         DDMMM #$(h "$DSHA") deep one with a very long subj

work
file:$WTIL/foreign/.be  remote
└┄┄ //FOR-4 ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄         DDMMM #$(h "$FSHA") foreign one

EOF
diff -u "$WORK/forest.want" "$WORK/forest.norm" >&2 || _fail "plain forest mismatch"
grep -q '\[get\]\|\[diff\]\|\[post\]\|\[done\]\|\[dont\]\|\[update\]\|\[merge\]\|\[rm' \
    "$WORK/forest.out" && _fail "plain leaks pager button chrome"
grep -q 'status //\|get ///\|post \x27\|diff //\|done \.\|dont \.\|/: ' "$WORK/forest.out" \
    && _fail "plain leaks a hidden spell"
grep -q 'junk\|README' "$WORK/forest.out" && _fail "plain lists work/junk or README"
grep -q "$(printf '\033')" "$WORK/forest.out" && _fail "plain carries styling (SGR)"

# --- 2. miss = ONE uniform WORKNONE line, non-zero exit ----------------------
if ( cd "$META" && "$BE" work BOGUS --plain ) > "$WORK/miss.out" 2>&1; then
    _fail "work BOGUS exited 0"; fi
grep -q 'work: BOGUS: WORKNONE' "$WORK/miss.out" || _fail "miss lacks the uniform WORKNONE line"

# --- 3. pager chrome: U navs + the BE-043 button tail on wt rows -------------
( cd "$META" && "$BE" work --tlv ) > "$WORK/forest.tlv" 2>/dev/null \
    || _fail "jab work --tlv failed"
[ -s "$WORK/forest.tlv" ] || _fail "work --tlv emitted ZERO bytes"

# --- 3a. WORK-005: the age fade END-TO-END through the real --color render ----
# `jab work --color` paints each wt row's default-fg by its tip age: PIN-1 (ext
# one, 8.5d) truecolor #888888, TRK-5 (ext two, 3.5d) #333333; the marker never
# leaks as visible text.  The SGR core is `38;2;R;G;B` (view/bro.js paintWhyRow).
# MUST run BEFORE the click legs (3b/check.js) — their real clicks bare-get/post
# the fixture wts, refreshing the aged rows the fade assertions pin.
ESC=$(printf '\033')
( cd "$META" && "$BE" work --color ) > "$WORK/forest.color" 2>/dev/null \
    || _fail "jab work --color failed"
grep -q "$ESC\[38;2;136;136;136m" "$WORK/forest.color" \
    || _fail "the 8+day PIN-1 row lacks the #888888 truecolor fade in --color"
grep -q "$ESC\[38;2;51;51;51m" "$WORK/forest.color" \
    || _fail "the 3-day TRK-5 row lacks the #333333 truecolor fade in --color"
grep -q '#888888\|#333333\|#000000' "$WORK/forest.color" \
    && _fail "an age-fade marker leaked as visible text in --color"

"$JABC" "$_CASE/check.js" "$WORK/forest.tlv" >"$WORK/check.out" 2>&1 \
    || { cat "$WORK/check.out" >&2; _fail "forest token assertions failed"; }

# --- 3b. WORK-004 pty: the REAL pager renders + clicks the ahbeh buttons ------
# A real pty.fork drives `jab work` from the TRK-5 wt: the frame must show the
# `[+N]`/`[-N]` ahbeh buttons and NO retired `[get]`; a real SGR mouse press on
# `[-N]` is accepted (pager exits clean) and leaves the LAUNCH tree's .be intact.
if command -v python3 >/dev/null 2>&1 && python3 -c "import pty,select" 2>/dev/null; then
    python3 "$_CASE/clickpty.py" "$JABC" "$META/work/TRK-5" "$META/work/TRK-5/.be" \
        > "$WORK/pty.out" 2>"$WORK/pty.err" \
        || { cat "$WORK/pty.out" "$WORK/pty.err" >&2; _fail "pty button session failed"; }
    grep -q "pty session done" "$WORK/pty.out" \
        || { cat "$WORK/pty.out" >&2; _fail "pty driver did not finish"; }
else
    echo "work/view: SKIP pty (no python3/pty)" >&2
fi

# --- 4. the [done]/[dont] verbs: mv into work/done/ + ticket flip ------------
# R2: the discard root is `work/done/` (same device, made on demand, IGNORED
# by the view); a name collision bumps `.2`, `.3`, … without clobbering.
DISC="$META/work/done"
# done: PIN-1 moves (work/done created by the verb) + header flips to [DONE].
( cd "$META/work/PIN-1" && "$BE" done . --plain ) \
    > "$WORK/done.out" 2>&1 || { cat "$WORK/done.out" >&2; _fail "jab done . failed"; }
[ ! -e "$META/work/PIN-1" ] || _fail "done left work/PIN-1 in place"
[ -d "$DISC/PIN-1" ] || _fail "done did not move PIN-1 into work/done/"
grep -q '^#   PIN-1 \[DONE\]: pin sample ticket$' "$META/todo/PIN/PIN-1.mkd" \
    || _fail "done did not flip the PIN-1 header to [DONE]"
# dont: DET-3 moves + its page header flips to [DONT].
( cd "$META/work/DET-3" && "$BE" dont . --plain ) \
    > "$WORK/dont.out" 2>&1 || { cat "$WORK/dont.out" >&2; _fail "jab dont . failed"; }
[ ! -e "$META/work/DET-3" ] || _fail "dont left work/DET-3 in place"
[ -d "$DISC/DET-3" ] || _fail "dont did not move DET-3 into work/done/"
grep -q '^#   DET-3 \[DONT\]: detached sample ticket$' "$META/todo/DET/DET-3.mkd" \
    || _fail "dont did not flip the DET-3 header to [DONT]"
# Collision: a pre-existing work/done/BR-2 must NOT be clobbered — the move bumps.
mkdir -p "$DISC/BR-2"; printf 'keep\n' > "$DISC/BR-2/keep.txt"
( cd "$META/work/BR-2" && "$BE" dont . --plain ) \
    > "$WORK/bump.out" 2>&1 || { cat "$WORK/bump.out" >&2; _fail "jab dont . (bump) failed"; }
[ ! -e "$META/work/BR-2" ] || _fail "dont (bump) left work/BR-2 in place"
[ -d "$DISC/BR-2.2" ] || _fail "collision did not bump to BR-2.2"
[ -f "$DISC/BR-2/keep.txt" ] || _fail "collision clobbered the existing BR-2"
[ ! -e "$META/todo/BR" ] || _fail "a page-less wt grew a ticket dir"
# Refusal: the main tree is NOT a work/ worktree — refuse loudly, move nothing.
if ( cd "$META" && "$BE" done . --plain ) > "$WORK/refuse.out" 2>&1; then
    _fail "done . on the main tree exited 0"; fi
[ -f "$META/R.txt" ] || _fail "done . moved the MAIN TREE"
grep -qi 'not a work' "$WORK/refuse.out" || _fail "refusal lacks a plain-words reason"
# The view IGNORES work/done/ entirely: the moved wts vanish from the forest.
( cd "$META" && "$BE" work --plain ) > "$WORK/after.out" 2>"$WORK/after.err" \
    || _fail "jab work after done/dont failed: $(cat "$WORK/after.err")"
grep -q '//PIN-1\|//DET-3\|//BR-2' "$WORK/after.out" \
    && _fail "the view still lists a discarded wt"
grep -q '//TRK-5' "$WORK/after.out" || _fail "the view lost a LIVE wt after discards"

echo "PASS [work/$NAME]"
