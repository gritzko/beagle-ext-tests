#!/bin/sh
# test/sub/wtsrc — GET-038: `jab get file:<worktree>?/<proj>` from a WORKTREE
# source must record the REAL STORE as the new wt's row-0 anchor, NOT the
# worktree path.  A worktree is NOT a store: its `.be` is a wtlog FILE that
# REDIRECTS (row-0 `repo|<storepath>`) to the real store.  Before GET-038 the
# get recorded the worktree URI, so a later `jab status` reopened that anchor,
# could not read the baseline commit's tree (no store there), got an EMPTY
# base, and classified every checked-out file as `unk` (the whole tree read
# untracked).  The store-form source (`file:<store>/.be?/<proj>`) anchored at
# the real store and status worked — that is the contrast this case pins.
#
# GET-038 fix (verbs/get/get.js seedLocal): when the local source PATH is a
# worktree (its `.be` is a FILE), follow that `.be`'s row-0 `repo` redirect to
# the real store dir and record THAT.  An unresolvable worktree source refuses
# with a friendly string and leaves NO broken/partial wt.
#
# TEST-003: project-less local `file:` clone (no keeper); no submodule mount —
# the source is a colocated primary store / its worktree, addressed `?/` (no
# project name — jab is single-shard project-less).
. "$(dirname "$0")/../lib/subcase.sh"

# --- build a project-less colocated primary store (the REAL store) ----------
# TEST-003: jab is single-shard project-less — refs live at .be/refs, the clone
# URI is `file:<store>/.be?/` (no project name).  PROJ kept only for legacy args.
STORE="$WORK/widget"
PROJ="widget"
rm -rf "$STORE"
mkdir -p "$STORE/.be"
( cd "$STORE"
  printf 'hello v1\n' > main.c
  printf 'lib v1\n'   > lib.c
  "$BE" post '#widget initial' >/dev/null 2>&1 ) || _fail "store setup"
TIP=$(sc_tip "$STORE" "$PROJ")
sc_is40 "$TIP" "widget tip"

# --- build a WORKTREE of the store (a SECONDARY wt) -------------------------
# Its `.be` is a wtlog FILE whose row-0 `repo` redirects to the real store —
# TEST-003: project-less shape (`repo file:<store>/.be/?/`, then the tip).
# A real `be status` here resolves the baseline (proves it is a valid worktree).
WTSRC="$WORK/work"
rm -rf "$WTSRC"; mkdir -p "$WTSRC"
cp "$STORE/main.c" "$STORE/lib.c" "$WTSRC/"
_R=$(awk -F'\t' 'NR==1{print $1; exit}' "$STORE/.be/wtlog")
printf '%s\trepo\tfile:%s/.be/?/\n%s\tget\t?#%s\n' \
    "$_R" "$STORE" "$_R" "$TIP" > "$WTSRC/.be"
( cd "$WTSRC" && "$BE" status ) >/dev/null 2>&1 \
    || _fail "worktree fixture: be status failed (not a valid wt)"

# ============================================================================
# GET from the WORKTREE source: the recorded anchor MUST be the real store, and
# `jab status` MUST classify (NOT all-`unk`).
# ============================================================================
T1="$WORK/getwt"
_rc=$(sc_jget "$T1" "file:$WTSRC?/")
[ "$_rc" = 0 ] || { echo "--- err ---"; cat "$WORK/last.err"; _fail "wt-source get exit $_rc"; }

# the checkout completed (files present).
[ -f "$T1/main.c" ] || _fail "wt-source get: main.c missing (checkout incomplete)"
[ -f "$T1/lib.c" ]  || _fail "wt-source get: lib.c missing (checkout incomplete)"

# row-0 anchor is the REAL STORE (`<store>/.be/?`), NOT the worktree path.
# URI-009: `ulog.write` composes the branch slot, so a project-LESS `?/` is
# emitted as the bare `?` — "`?` the trunk" ([/wiki/URI]); only a NAMED `?/proj`
# keeps its slot.  The pattern QUOTES the `?`: unquoted it is a shell glob (one
# any-char), which silently weakened this very assertion.
_row0=$(awk -F'\t' 'NR==1{print $3; exit}' "$T1/.be")
case "$_row0" in
    file:"$STORE"/.be/"?") ;;
    *) _fail "wt-source get: row-0 anchor [$_row0] != real store file:$STORE/.be/?" ;;
esac
# explicitly NOT the worktree URI (the GET-038 bug).
case "$_row0" in
    *"$WTSRC"*) _fail "wt-source get: row-0 still records the WORKTREE path [$_row0]" ;;
esac
echo "ok   wt-source get recorded the real store anchor: $_row0"

# `jab status` in the new wt classifies — the baseline resolves, so the clean
# checkout reads 0-modified / no `unk` (NOT the all-`unk` GET-038 symptom).
# BRO-030 quad default: an unresolved baseline would surface untracked `...o` rows;
# a clean classified checkout emits none, only the summary frame line.
_st=$( ( cd "$T1" && "$JABC" status ) 2>"$WORK/st.err" )
echo "$_st" | grep -qE '\.\.\.o ' && { echo "$_st"; _fail "wt-source get: status reports untracked ...o (baseline unresolvable — GET-038)"; }
echo "$_st" | grep -q '^?' || { echo "$_st"; _fail "wt-source get: status did not classify against the baseline (no summary)"; }
echo "ok   jab status classifies against the real baseline (no all-\`unk\`)"

# Contrast: the STORE-form source records the SAME real-store anchor (unchanged).
T2="$WORK/getstore"
_rc=$(sc_jget "$T2" "file:$STORE/.be?/")
[ "$_rc" = 0 ] || { echo "--- err ---"; cat "$WORK/last.err"; _fail "store-form get exit $_rc"; }
_srow0=$(awk -F'\t' 'NR==1{print $3; exit}' "$T2/.be")
[ "$_srow0" = "$_row0" ] \
    || _fail "store-form anchor [$_srow0] != wt-source anchor [$_row0] (must converge on the store)"
echo "ok   store-form source records the identical real-store anchor"

# ============================================================================
# FRIENDLY REFUSE: a worktree source whose `.be` carries NO store redirect must
# refuse with a friendly string and leave NO broken/partial wt.
# ============================================================================
BADWT="$WORK/badwt"
rm -rf "$BADWT"; mkdir -p "$BADWT"
: > "$BADWT/.be"                                 # empty anchor: no row-0 redirect
T3="$WORK/getbad"
_rc=$(sc_jget "$T3" "file:$BADWT?/")
[ "$_rc" = 0 ] && _fail "unresolvable wt-source get should FAIL, got exit 0"
grep -q 'GETWTSRC' "$WORK/last.err" \
    || { cat "$WORK/last.err"; _fail "unresolvable wt-source: not the friendly GETWTSRC refuse"; }
[ -e "$T3/.be" ] && _fail "unresolvable wt-source: left a broken/partial wt (.be present)"
echo "ok   unresolvable worktree source refuses cleanly (GETWTSRC, no partial wt)"

pass
