#!/bin/sh
# test/todo/meta — TODO-004: the `todo` view's META-PAIR layer.  The ticket
# STATE left the header for the [/meta/todo] pairs, so the board's open filter
# is now the `Now:` pair answered through the [TODO-003] index
# (shared/metaidx.js), with the old header mark kept only as the legacy
# fallback; `Sev:` replaced the priority marks the same way.  RED before the
# fix: a `Now: DONE` ticket with no header mark boarded as OPEN (on the live
# tree 424 of 878 tickets — the header grep had gone dead).
#
# The ARG GRAMMAR (ruling 2026-08-03) is an arg LINE, not a positional call: a
# topic OR a ticket id, plus any number of `Key:Value` filters, in any order.
#   todo                 the open board       todo ABC        one topic
#   todo ABC-123         one ticket page      todo Now:OPEN   one filter
#   todo ABC Now:OPEN    a topic AND a filter
#   todo Who:gritzko Sev:HIGH    two keys — they AND
#   todo Now:OPEN Now:DONE       one key twice — it ORs
#   todo Rev:*           presence             todo Due:       absent-or-empty
# Spaces and colons SEPARATE, so a second colon in one token is an error in
# plain words, never an OR shorthand, and a value carrying either is
# presence-filterable only.  A bare key with no colon is an error pointing at
# `Key:*`.  With no `Now:` in the line the listing hides `Now:DONE` and
# `Now:DONT` ONLY — `Now:STALE` and pair-less tickets stay listed — and any
# mention of `Now:` overrides that default.  Flat filter results order by
# topic+number (time-sort is POSTPONED, so there is no freshness order here).
# Registered by the be/test glob as be-js-todo-meta — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/todo/meta
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "todo/meta: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "todo/meta: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/shared/metaidx.js" ] || { echo "todo/meta: SKIP — no metaidx.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=meta
WORK="$TMP/$$/todo/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [todo/$NAME] $*" >&2; exit 1; }
# `grep -q` on a listing, said once: has/hasnt <file> <pattern> <why>
_has()  { grep -q "$2" "$1" || _fail "$3 (missing $2)"; }
_hasnt(){ grep -q "$2" "$1" && _fail "$3 (unexpected $2)" || true; }
# The 1-based line number of the first row for KEY in a listing.
_at() { grep -n "^ *$2" "$1" | head -1 | cut -d: -f1; }
# a < b in the listing?
_before() {
    _a=$(_at "$1" "$2"); _b=$(_at "$1" "$3")
    [ -n "$_a" ] && [ -n "$_b" ] || _fail "$4 ($2=$_a $3=$_b — a row is missing)"
    [ "$_a" -lt "$_b" ] || _fail "$4 ($2 at $_a is not before $3 at $_b)"
}
# A refusal: non-zero exit AND the plain-words line, never a bare code.
_refuses() {
    _why=$1; shift
    if "$BE" todo "$@" --plain > "$WORK/refuse.out" 2>&1; then
        _fail "$_why: 'todo $*' exited 0"
    fi
    grep -q "$_why" "$WORK/refuse.out" \
        || _fail "'todo $*' did not refuse in plain words: $(cat "$WORK/refuse.out")"
}

# --- the fixture: the worktree the loop runs from IS the project root -------
# URI-016: todoRoot() is <project root>/todo and projectRoot() is the topmost
# `.be`-anchored dir above the cwd, so the tickets live under $WT.  The meta
# index lives in the project STORE, so the tree is `post`ed before any query.
WT="$WORK/wt"; mkdir -p "$WT/.be" "$WT/todo/TST" "$WT/todo/OTH"

# TST-001/002 are open and severity-ranked; TST-003 is `Now: DONE` with NO
# header mark — the dead-filter repro; TST-004 is STALE (which the default
# filter must NOT hide); TST-005 carries NO pairs at all (un-migrated: reads
# open); TST-006 carries only the LEGACY header mark (the fallback must still
# close it); TST-007 is `Now: DONT`; TST-008 carries an EMPTY `Who:`.
cat > "$WT/todo/TST/TST-001.mkd" <<'EOF'
#   TST-001: open alpha
Now: OPEN
Sev: HIGH
Who: gritzko
EOF
cat > "$WT/todo/TST/TST-002.mkd" <<'EOF'
#   TST-002: open beta
Now: OPEN
Sev: CRIT
Who: ann
EOF
cat > "$WT/todo/TST/TST-003.mkd" <<'EOF'
#   TST-003: closed by the pair, no header mark at all
Now: DONE
Sev: LOW
Who: gritzko
EOF
cat > "$WT/todo/TST/TST-004.mkd" <<'EOF'
#   TST-004: superseded but still listed
Now: STALE
EOF
cat > "$WT/todo/TST/TST-005.mkd" <<'EOF'
#   TST-005: un-migrated, no meta pairs at all
EOF
cat > "$WT/todo/TST/TST-006.mkd" <<'EOF'
#   TST-006 [DONE]: the LEGACY header mark still closes a pair-less ticket
EOF
cat > "$WT/todo/TST/TST-007.mkd" <<'EOF'
#   TST-007: will not do
Now: DONT
EOF
cat > "$WT/todo/TST/TST-008.mkd" <<'EOF'
#   TST-008: unassigned, the Who: pair is EMPTY
Now: OPEN
Who:
EOF
# TST-009 carries a PLAINLY INDENTED header block (four spaces — the live
# todo/TODO/TODO-003 shape).  The column-0 line regex never indexed it, so it
# rendered and CLICKED but its own `Sev:` click answered "no ticket matches".
cat > "$WT/todo/TST/TST-009.mkd" <<'EOF'
#   TST-009: the four-space indented header block
    Now: OPEN
    Sev: MED
EOF
# TST-010: the other half — indent-tolerance ALONE is wrong.  A pair that
# appears after another construct has intervened belongs to THAT construct, not
# to the ticket ([/meta/todo]: meta pairs go directly under the header).  Both
# shapes are here: a four-space `Fix:` nested in a WIP bullet (the live
# POST-023/CODE-019/BRO-005 shape) and a column-0 `Msg:` deep in the body.
cat > "$WT/todo/TST/TST-010.mkd" <<'EOF'
#   TST-010: only the block under the header is ticket meta
Now: OPEN

##  WIP

 -  a bullet with a nested pair
    Fix: this belongs to the bullet, not to the ticket

Msg: and this one is late, so it is not ticket meta either
EOF
# TST-011: an ILLEGAL indent (two spaces) is not a meta header at all.
cat > "$WT/todo/TST/TST-011.mkd" <<'EOF'
#   TST-011: two spaces is not a legal meta indent
  Now: DONE
EOF
cat > "$WT/todo/OTH/OTH-001.mkd" <<'EOF'
#   OTH-001: later deadline
Now: OPEN
Due: 2026-09-01
Rev: file:/a/branch/uri
Who: Ann Example
EOF
cat > "$WT/todo/OTH/OTH-002.mkd" <<'EOF'
#   OTH-002: earlier deadline
Now: OPEN
Due: 2026-08-01
EOF

cd "$WT"
printf 'seed\n' > a.txt
"$BE" post 'seed commit' >/dev/null 2>&1 || _fail "seed post"

# --- 1. the board: the `Now:` pair decides, the header mark is the fallback --
"$BE" todo --plain > "$WORK/board.out" 2>"$WORK/board.err" \
    || _fail "jab todo failed: $(cat "$WORK/board.err")"
_has   "$WORK/board.out" 'TST-001' "board misses an open ticket"
_has   "$WORK/board.out" 'TST-002' "board misses an open ticket"
_has   "$WORK/board.out" 'TST-005' "board drops the un-migrated (pair-less) ticket"
_has   "$WORK/board.out" 'OTH-001' "board misses the second topic"
_hasnt "$WORK/board.out" 'TST-003' "board still lists a Now: DONE ticket — the dead header grep"
_hasnt "$WORK/board.out" 'TST-007' "board lists a Now: DONT ticket"
_hasnt "$WORK/board.out" 'TST-006' "board lists a ticket the LEGACY [DONE] header mark closes"
# ruling 2026-08-03: the default hides DONE and DONT ONLY — STALE stays listed.
_has   "$WORK/board.out" 'TST-004' "the default filter hid a Now: STALE ticket"
# no filter in the arg line => no key is queried => no inline value bracket.
_hasnt "$WORK/board.out" 'TST-001 \[OPEN\]' "the bare board shows an un-queried value inline"

# --- 1b. `Sev:` orders a topic the way the priority marks used to ------------
_before "$WORK/board.out" 'TST-002' 'TST-001' "Sev: CRIT does not sort above HIGH"
_before "$WORK/board.out" 'TST-001' 'TST-005' "Sev: HIGH does not sort above an unranked ticket"

# --- 2. `todo TOPIC` obeys the same filter; the page ignores it entirely -----
"$BE" todo TST --plain > "$WORK/topic.out" 2>&1 || _fail "jab todo TST failed"
_has   "$WORK/topic.out" 'TST-001' "topic list misses an open ticket"
_hasnt "$WORK/topic.out" 'TST-003' "topic list lists a Now: DONE ticket"
_hasnt "$WORK/topic.out" 'OTH-001' "topic list leaks the other topic"
"$BE" todo TST-003 --plain > "$WORK/page.out" 2>&1 || _fail "jab todo TST-003 failed"
_has "$WORK/page.out" 'closed by the pair' "direct addressing did not render a closed ticket"
_has "$WORK/page.out" 'Now: DONE' "the page did not render its meta-pair block"

# --- 3. `todo Key:Value` — one filter, every topic --------------------------
"$BE" todo Now:OPEN --plain > "$WORK/open.out" 2>&1 || _fail "jab todo Now:OPEN failed"
_has   "$WORK/open.out" 'TST-001 \[OPEN\]' "a filter does not show the queried value inline"
_has   "$WORK/open.out" 'OTH-001' "todo Now:OPEN misses the other topic"
_hasnt "$WORK/open.out" 'TST-003' "todo Now:OPEN leaked a DONE ticket"
_hasnt "$WORK/open.out" 'TST-004' "todo Now:OPEN leaked a STALE ticket"
_hasnt "$WORK/open.out" 'TST-005' "todo Now:OPEN leaked a pair-less ticket"
# flat results order by TOPIC then NUMBER (time-sort is postponed).
_before "$WORK/open.out" 'OTH-001' 'OTH-002' "flat results are not number-ordered"
_before "$WORK/open.out" 'OTH-002' 'TST-001' "flat results are not topic-ordered"

# --- 3b. `todo TOPIC Key:Value` — a topic AND a filter ----------------------
"$BE" todo TST Now:OPEN --plain > "$WORK/tstopen.out" 2>&1 || _fail "jab todo TST Now:OPEN failed"
_has   "$WORK/tstopen.out" 'TST-001' "todo TST Now:OPEN misses its ticket"
_hasnt "$WORK/tstopen.out" 'OTH-001' "todo TST Now:OPEN leaked the other topic"
_hasnt "$WORK/tstopen.out" 'TST-003' "todo TST Now:OPEN leaked a DONE ticket"

# --- 3c. two keys AND; the order of the args does not matter ----------------
"$BE" todo Who:gritzko Sev:HIGH --plain > "$WORK/and.out" 2>&1 || _fail "jab todo Who:gritzko Sev:HIGH failed"
_has   "$WORK/and.out" 'TST-001 \[gritzko\] \[HIGH\]' "an AND query does not show both queried values inline"
_hasnt "$WORK/and.out" 'TST-002' "the AND leaked a ticket matching only Sev:"
_hasnt "$WORK/and.out" 'TST-003' "the AND leaked a ticket matching only Who:"
"$BE" todo Sev:HIGH Who:gritzko --plain > "$WORK/and2.out" 2>&1 || _fail "jab todo Sev:HIGH Who:gritzko failed"
_has   "$WORK/and2.out" 'TST-001' "arg ORDER changed the AND answer"

# --- 3d. repeating a key ORs it ---------------------------------------------
"$BE" todo TST Now:OPEN Now:DONE --plain > "$WORK/or.out" 2>&1 || _fail "jab todo TST Now:OPEN Now:DONE failed"
_has   "$WORK/or.out" 'TST-001' "the OR lost the first value"
_has   "$WORK/or.out" 'TST-003' "the OR lost the second value"
_hasnt "$WORK/or.out" 'TST-004' "the OR leaked a third value (STALE)"

# --- 3e. `Key:*` = present with any value; `Key:` = not defined or empty ----
"$BE" todo 'Rev:*' --plain > "$WORK/star.out" 2>&1 || _fail "jab todo Rev:* failed"
_has   "$WORK/star.out" 'OTH-001' "Rev:* misses the one ticket carrying the key"
_hasnt "$WORK/star.out" 'OTH-002' "Rev:* leaked a ticket lacking the key"
"$BE" todo TST 'Who:*' --plain > "$WORK/whostar.out" 2>&1 || _fail "jab todo TST Who:* failed"
_has   "$WORK/whostar.out" 'TST-001' "Who:* misses a ticket carrying a value"
_hasnt "$WORK/whostar.out" 'TST-008' "Who:* matched an EMPTY value — presence means a value"
"$BE" todo TST Who: --plain > "$WORK/whonone.out" 2>&1 || _fail "jab todo TST Who: failed"
_has   "$WORK/whonone.out" 'TST-008' "Who: misses the ticket whose pair is EMPTY"
_has   "$WORK/whonone.out" 'TST-005' "Who: misses the ticket that lacks the key"
_hasnt "$WORK/whonone.out" 'TST-001' "Who: leaked a ticket that HAS a value"

# --- 4. the `Now:` default and its override ---------------------------------
"$BE" todo TST Sev:LOW --plain > "$WORK/deflt.out" 2>&1 || _fail "jab todo TST Sev:LOW failed"
_hasnt "$WORK/deflt.out" 'TST-003' "a Now:-less query listed a DONE ticket"
"$BE" todo Now:DONE --plain > "$WORK/done.out" 2>&1 || _fail "jab todo Now:DONE failed"
_has   "$WORK/done.out" 'TST-003' "todo Now:DONE cannot reach the closed tickets"
_hasnt "$WORK/done.out" 'TST-001' "todo Now:DONE leaked an open ticket"
"$BE" todo TST 'Now:*' --plain > "$WORK/nowstar.out" 2>&1 || _fail "jab todo TST Now:* failed"
_has   "$WORK/nowstar.out" 'TST-003' "Now:* does not override the default hide"
_has   "$WORK/nowstar.out" 'TST-007' "Now:* does not reach a DONT ticket"

# --- 4b. the INDENT ruling: column 0 and four spaces, nothing else ----------
# RED before the fix: metaidx's PAIR regex was anchored at column 0, so an
# indented header indexed as NOTHING — the page rendered `Sev: MED` and the
# click composed `todo TST Sev:MED`, which then answered "no ticket matches".
"$BE" todo TST Sev:MED --plain > "$WORK/indent.out" 2>&1 || _fail "jab todo TST Sev:MED failed"
_has "$WORK/indent.out" 'TST-009 \[MED\]' "an indented meta header still does not index"
"$BE" todo TST Now:OPEN --plain > "$WORK/indent2.out" 2>&1 || _fail "jab todo TST Now:OPEN failed"
_has "$WORK/indent2.out" 'TST-009' "an indented Now: pair does not answer its own filter"
# a two-space indent is NOT a meta header — the ticket reads pair-less, so it
# boards (fail-open) and no `Now:` query reaches it.
"$BE" todo TST 'Now:*' --plain > "$WORK/illegal.out" 2>&1 || _fail "jab todo TST Now:* failed"
_hasnt "$WORK/illegal.out" 'TST-011' "a two-space indent was read as a meta header"
_has   "$WORK/board.out" 'TST-011' "the pair-less (illegally indented) ticket left the board"

# --- 4c. SCOPE: only the block directly under the header is ticket meta -----
# The six live `Fix:`/`Msg:` pairs (POST-023, CODE-019, POST-031, BLAME-006,
# PATCH-004, BRO-005) sit four-space indented inside a WIP bullet — lexically
# legal, but they are the bullet's, not the ticket's.  A fix that only relaxed
# the indent would let `Fix:*` answer with all six.
"$BE" todo 'Fix:*' --plain > "$WORK/scope.out" 2>&1 || _fail "jab todo Fix:* failed"
_hasnt "$WORK/scope.out" 'TST-010' "a pair nested in a bullet became ticket meta"
"$BE" todo 'Msg:*' --plain > "$WORK/scope2.out" 2>&1 || _fail "jab todo Msg:* failed"
_hasnt "$WORK/scope2.out" 'TST-010' "a late column-0 pair became ticket meta"
_has   "$WORK/tstopen.out" 'TST-010' "the header block itself stopped answering"

# --- 5. a value carrying a space rides its DESPACED index form --------------
"$BE" todo Who:AnnExample --plain > "$WORK/space.out" 2>&1 || _fail "jab todo Who:AnnExample failed"
_has "$WORK/space.out" 'OTH-001' "a despaced value does not match its spaced pair"

# --- 6. refusals: plain words for every new class ---------------------------
_refuses 'carries two colons'            Now:OPEN:DONE
_refuses 'is not a meta key'             now:OPEN
_refuses 'is a meta key with no value'   Now
_refuses 'is not a ticket code, a topic or a Key:Value filter'  notakey
_refuses 'names one ticket page'         TST-001 Now:OPEN
_refuses 'one topic or one ticket id at a time'  TST OTH
_hasnt "$WORK/refuse.out" 'TODONONE' "a plain-words refusal leaked a bare code"
if "$BE" todo TST-999 --plain > "$WORK/miss.out" 2>&1; then _fail "todo TST-999 exited 0"; fi
_has "$WORK/miss.out" 'todo: TST-999: TODONONE' "the missing-ticket line changed"

# --- 7. the click SPELLS carry the WHOLE arg line (the tlv the pager reads) -
"$BE" todo TST-001 --tlv > "$WORK/page.tlv" 2>/dev/null || _fail "jab todo TST-001 --tlv failed"
[ -s "$WORK/page.tlv" ] || _fail "todo TST-001 --tlv emitted ZERO bytes"
"$JABC" "$_CASE/check.js" "$WORK/page.tlv" page >"$WORK/c1.out" 2>&1 \
    || { cat "$WORK/c1.out" >&2; _fail "page meta-pair spell assertions failed"; }
"$BE" todo TST 'Now:*' 'Sev:*' --tlv > "$WORK/list.tlv" 2>/dev/null || _fail "jab todo TST Now:* Sev:* --tlv failed"
"$JABC" "$_CASE/check.js" "$WORK/list.tlv" list >"$WORK/c2.out" 2>&1 \
    || { cat "$WORK/c2.out" >&2; _fail "list-row value spell assertions failed"; }
"$BE" todo OTH-001 --tlv > "$WORK/uri.tlv" 2>/dev/null || _fail "jab todo OTH-001 --tlv failed"
"$JABC" "$_CASE/check.js" "$WORK/uri.tlv" uri >"$WORK/c3.out" 2>&1 \
    || { cat "$WORK/c3.out" >&2; _fail "un-expressible-value spell assertions failed"; }
# an INDENTED block clicks exactly like a column-0 one, and a pair the SCOPE
# rule rejects carries no click at all — one matcher answers render and index.
"$BE" todo TST-009 --tlv > "$WORK/indent.tlv" 2>/dev/null || _fail "jab todo TST-009 --tlv failed"
"$JABC" "$_CASE/check.js" "$WORK/indent.tlv" indent >"$WORK/c4.out" 2>&1 \
    || { cat "$WORK/c4.out" >&2; _fail "indented meta-block spell assertions failed"; }
"$BE" todo TST-010 --tlv > "$WORK/scope.tlv" 2>/dev/null || _fail "jab todo TST-010 --tlv failed"
"$JABC" "$_CASE/check.js" "$WORK/scope.tlv" scope >"$WORK/c5.out" 2>&1 \
    || { cat "$WORK/c5.out" >&2; _fail "out-of-scope pair spell assertions failed"; }

echo "PASS [todo/$NAME]"
