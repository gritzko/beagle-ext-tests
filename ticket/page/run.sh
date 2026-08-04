#!/bin/sh
# test/ticket/page — TODO-011: the one-ticket PAGE is its own view, `ticket`.
#
# The RED/GREEN baseline of the split is BYTE PARITY: `ticket ABC-123` must
# render what `todo ABC-123` rendered before it, modulo the in-page spells now
# saying `ticket`.  So the case pins the page bytes themselves (a THIN
# `todo/PAG/PAG-001.mkd` and a FAT `todo/PAG/PAG-002/README.mkd`) against the
# committed goldens captured off the pre-split `todo` view, and asserts the
# spell sweep over the --tlv the pager reads:
#   in-page bare key / `[KEY]` reflink / ticket-VALUED meta pair -> `ticket KEY`
#   in-page meta KEY half and non-ticket meta VALUE half         -> `todo …`
#     (a filter narrows a LISTING and listings are the board's business)
#   a non-ticket in-tree reflink target                          -> `cat <rel>`
# ...plus the two refusal families, both PLAIN WORDS and never a bare code:
#   `todo PAG-001`  -> points at `ticket PAG-001` (and at `todo PAG`)
#   `ticket PAG` / `ticket Now:OPEN` / bare `ticket` -> point at `todo …`
# A page is not a listing, so a CLOSED ticket renders by key exactly like an
# open one (the fail-open spirit of the board's own direct addressing).
# Registered by the be/test glob as be-js-ticket-page — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/ticket/page
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "ticket/page: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "ticket/page: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/views/ticket/ticket.js" ] || { echo "ticket/page: SKIP — no ticket view" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=page
WORK="$TMP/$$/ticket/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [ticket/$NAME] $*" >&2; exit 1; }
_has()  { grep -q "$2" "$1" || _fail "$3: $(cat "$1")"; }
_hasnt(){ grep -q "$2" "$1" && _fail "$3: $(cat "$1")"; return 0; }

# --- the worktree the loop runs from == the PROJECT ROOT --------------------
# URI-016: todoRoot() is <project root>/todo, and projectRoot() is the TOPMOST
# `.be`-anchored dir above the cwd, so the fixture ticket tree lives under $WT.
WT="$WORK/wt"; mkdir -p "$WT/.be" "$WT/todo/PAG/PAG-002" "$WT/wiki"

# The THIN page: meta pairs (a plain one, a ticket-VALUED one, and an
# UNREGISTERED key with a ticket-shaped value), a bare key mention, a `[KEY]`
# reflink, a named reflink and a `/pocket/Page` shortcut.
cat > "$WT/todo/PAG/PAG-001.mkd" <<'EOF'
#   PAG-001: thin parity ticket
Now: OPEN
Sev: MED
See: PAG-002
Zzz: PAG-003

Body mentions PAG-002 bare, and [PAG-003] as a bracketed key.

##  Input
 -  see [W] for the wiki page.
 -  see [/wiki/Sample] for the shortcut form.

[W]: ../../wiki/Sample.mkd "a wiki page reflink"
EOF
# The FAT page: same features, one dir deeper (its reflinks climb one more).
cat > "$WT/todo/PAG/PAG-002/README.mkd" <<'EOF'
#   PAG-002: fat parity ticket (dir layout)
Now: OPEN
Sev: HIGH
Sub: PAG-001
Rev: http://example.org/x

A fat ticket lives at todo/PAG/PAG-002/README.mkd and mentions PAG-001
and [PAG-003] and [W].

##  Input
 -  [/wiki/Sample] shortcut.

[W]: ../../../wiki/Sample.mkd "a wiki page reflink"
EOF
cat > "$WT/todo/PAG/PAG-003.mkd" <<'EOF'
#   PAG-003: third parity ticket
Now: OPEN
EOF
# CLOSED by the `Now:` pair — a page is not a listing, so it still renders.
cat > "$WT/todo/PAG/PAG-004.mkd" <<'EOF'
#   PAG-004: closed parity ticket
Now: DONE
EOF
cat > "$WT/wiki/Sample.mkd" <<'EOF'
#   Sample wiki page

Wiki body.
EOF

cd "$WT"
printf 'seed\n' > a.txt
"$BE" post 'seed commit' >/dev/null 2>&1 || _fail "seed post"

# --- 1. PAGE PARITY: the rendered bytes vs the pre-split goldens ------------
# `--plain` is the page verbatim behind its banner; the banner is the ONE byte
# run the split was allowed to move (`todo KEY` -> `ticket KEY`).
for k in PAG-001 PAG-002; do
    "$BE" ticket $k --plain > "$WORK/$k.plain" 2>&1 || _fail "jab ticket $k failed"
    cmp -s "$WORK/$k.plain" "$_CASE/golden/$k.plain" \
        || { diff -u "$_CASE/golden/$k.plain" "$WORK/$k.plain" >&2 || true
             _fail "$k page bytes drifted from the pre-split golden"; }
done

# --- 2. the SPELL SWEEP over the tlv the pager reads ------------------------
for k in PAG-001 PAG-002; do
    "$BE" ticket $k --tlv > "$WORK/$k.tlv" 2>/dev/null || _fail "jab ticket $k --tlv failed"
    [ -s "$WORK/$k.tlv" ] || _fail "ticket $k --tlv emitted ZERO bytes"
    "$JABC" "$_CASE/check.js" "$WORK/$k.tlv" $k >"$WORK/$k.chk" 2>&1 \
        || { cat "$WORK/$k.chk" >&2; _fail "$k spell assertions failed"; }
    sed 's/^/     /' "$WORK/$k.chk"
done

# --- 3. a page is NOT a listing: a closed ticket renders by key -------------
"$BE" ticket PAG-004 --plain > "$WORK/closed.out" 2>&1 || _fail "jab ticket PAG-004 (closed) failed"
_has "$WORK/closed.out" 'closed parity ticket' "a closed ticket's page did not render"
# ...and it is still absent from the board (todo/ listings keep filtering).
"$BE" todo PAG --plain > "$WORK/list.out" 2>&1 || _fail "jab todo PAG failed"
_hasnt "$WORK/list.out" 'PAG-004' "the closed ticket leaked into the topic list"

# --- 4. `todo <KEY>` refuses in PLAIN WORDS, pointing at `ticket <KEY>` -----
if "$BE" todo PAG-001 --plain > "$WORK/r1.out" 2>&1; then _fail "todo PAG-001 exited 0"; fi
_has "$WORK/r1.out" "write 'ticket PAG-001' for the page" "todo KEY does not point at the ticket view"
_has "$WORK/r1.out" "'todo PAG' for the topic" "todo KEY drops the topic-list pointer"
_hasnt "$WORK/r1.out" 'TODONONE' "the todo KEY refusal leaked a bare code"
# a filter alongside the id changes nothing — a page is still not a listing
if "$BE" todo PAG-001 Now:OPEN --plain > "$WORK/r2.out" 2>&1; then _fail "todo PAG-001 Now:OPEN exited 0"; fi
_has "$WORK/r2.out" "write 'ticket PAG-001' for the page" "todo KEY+filter lost the pointer"
_has "$WORK/r2.out" "'todo PAG Now:OPEN'" "todo KEY+filter drops the filter from its pointer"

# --- 5. `ticket` refuses every NON-KEY arg, pointing at `todo` --------------
if "$BE" ticket --plain > "$WORK/r3.out" 2>&1; then _fail "bare ticket exited 0"; fi
_has "$WORK/r3.out" "which ticket?" "bare ticket does not ask for one"
_has "$WORK/r3.out" "'todo' for the open board" "bare ticket does not point at the board"
if "$BE" ticket PAG --plain > "$WORK/r4.out" 2>&1; then _fail "ticket PAG (topic) exited 0"; fi
_has "$WORK/r4.out" "'PAG' names a topic" "ticket TOPIC does not name the class"
_has "$WORK/r4.out" "write 'todo PAG'" "ticket TOPIC does not point at the topic list"
if "$BE" ticket Now:OPEN --plain > "$WORK/r5.out" 2>&1; then _fail "ticket Now:OPEN exited 0"; fi
_has "$WORK/r5.out" "is a filter" "ticket FILTER does not name the class"
_has "$WORK/r5.out" "write 'todo Now:OPEN'" "ticket FILTER does not point at the filter listing"
if "$BE" ticket PAG-001 Now:OPEN --plain > "$WORK/r6.out" 2>&1; then _fail "ticket KEY+filter exited 0"; fi
_has "$WORK/r6.out" "write 'todo PAG Now:OPEN'" "ticket KEY+filter points nowhere useful"
# a MISSING ticket is plain words too — never the board's legacy bare code
if "$BE" ticket PAG-999 --plain > "$WORK/r7.out" 2>&1; then _fail "ticket PAG-999 exited 0"; fi
_has "$WORK/r7.out" 'there is no ticket PAG-999' "the ticket miss line changed"
_hasnt "$WORK/r7.out" 'TODONONE' "the ticket miss leaked a bare code"
echo "PASS [ticket/$NAME]"
