#!/bin/sh
# test/get/empty-be — GET-060: `be get <wire remote>` into a dir whose OWN `.be`
# is EMPTY/unanchored is a GREEN-FIELD clone, not an update.  `be.treeAt` calls
# an empty `.be/` an established worktree (it anchors: the dir exists), so the
# GET-041 guard — which rejects only an ANCESTOR anchor — let the UPDATE leg
# run on a first-ever clone: the pack landed FLAT in `.be/0000000001.keeper`,
# `appendGetRow` wrote the tip row alone (no `file:…/.be/<proj>/` ANCHOR row),
# no shard was minted, and the run died in `commitTree("")` with a bare
# `TypeError: Invalid argument type in ToBigInt operation` before any checkout.
# RULING (gritzko 2026-08-06): a store `.be/` holds ANY NUMBER of shards and the
# shard path is ALWAYS `.be/<shard>/*.keeper` — there is no flat store.
#
# Three shapes, one source, one wire leg:
#   own-empty  a pre-made EMPTY `.be/` dir      (RED before the fix)
#   nobe       no `.be` at all                  (green today — regression guard)
#   anc/child  `.be` only in an ANCESTOR dir    (green today — GET-041 Control B)
# Each must end with `.be/<proj>/*.keeper`, NO flat pack under `.be/`, BOTH
# wtlog rows (anchor + tip) and a complete checkout.
. "$(dirname "$0")/../../lib/getrepro.sh"

# The `be:` host-less remote is a LOCAL wire leg (seedRemote, not seedLocal) —
# POST-028 spawns THIS jab as the peer (`jab upload-pack`), so the case is
# hermetic and needs no native keeper on the box.
KEEPER_BIN=$JABC; export KEEPER_BIN

# The source repo.  Spelled out (not gr_src) because gr_src is called in a
# command substitution everywhere else and its `cd` would not survive one —
# every seeding `jab` below MUST run inside $SRC, never in the caller's cwd.
SRC="$WORK/src"; mkdir -p "$SRC"; cd "$SRC"; mkdir .be
printf 'A\n' > a.txt; printf 'B\n' > b.txt
mkdir d; printf 'C\n' > d/c.txt
"$BE" post 'c1' >/dev/null 2>&1
# DIS-076: a bare post moves no ref, so the wire advert would have nothing to
# serve — post the trunk so the peer advertises `?`.
"$BE" post '?' >/dev/null 2>&1
REMOTE="be:$SRC/.be"

# eb_wtlog_has DIR PATTERN — assert the CLONE's wtlog carries a matching row.
# A remote clone is a PRIMARY wt (`.be/` dir, wtlog inside it), so gr_wtlog_has
# — which dumps the `.be` FILE a local/secondary clone writes — reads nothing.
eb_wtlog_has() {
    _raw=$(od -An -c "$1/.be/wtlog" 2>/dev/null | tr -d ' \n' | sed 's/\\t//g; s/\\n//g')
    printf '%s' "$_raw" | grep -qE "$2" \
        || { echo "--- wtlog dump ---"; printf '%s\n' "$_raw"; \
             _fail "$3: wtlog lacks pattern: $2"; }
}

# eb_clone DIR LABEL — clone into DIR (must exist), then assert the FULL shape.
eb_clone() {
    _d=$1; _lab=$2
    _rc=$(gr_jget "$_d" "$REMOTE")
    [ "$_rc" = 0 ] || { cat "$WORK/last.err"; _fail "$_lab: get exited $_rc"; }
    # 1. the shard: `.be/<proj>/` carries the pack (the ruling's ONLY layout).
    _shard=$(find "$_d/.be" -mindepth 2 -maxdepth 2 -name '*.keeper' 2>/dev/null | head -1)
    [ -n "$_shard" ] || { find "$_d/.be"; _fail "$_lab: no .be/<proj>/*.keeper shard"; }
    # 2. NO flat store: a pack directly under `.be/` is out of spec.
    _flat=$(find "$_d/.be" -maxdepth 1 -name '*.keeper' 2>/dev/null | head -1)
    [ -z "$_flat" ] || _fail "$_lab: FLAT pack under .be/ ($_flat)"
    # 3. the ANCHOR row names that shard, and the TIP row follows it.
    _proj=$(basename "$(dirname "$_shard")")
    eb_wtlog_has "$_d" "get.*file:.*/\.be/$_proj/" "$_lab"
    eb_wtlog_has "$_d" "get.*\?#[0-9a-f]{40}" "$_lab"
    # 4. the checkout ran to completion.
    gr_file_is "$_d/a.txt" A
    gr_file_is "$_d/b.txt" B
    gr_file_is "$_d/d/c.txt" C
}

# --- shape 1: the repro — the dir's OWN `.be` exists but is EMPTY -----------
mkdir -p "$WORK/own-empty/.be"
eb_clone "$WORK/own-empty" own-empty

# --- shape 2: no `.be` at all (the classic green field) ---------------------
mkdir -p "$WORK/nobe"
eb_clone "$WORK/nobe" nobe

# --- shape 3: an ANCESTOR carries the only `.be` (GET-041 Control B) --------
mkdir -p "$WORK/anc/.be"
( cd "$WORK/anc" && printf 'X\n' > x.txt && "$BE" post 'anc' ) >/dev/null 2>&1
mkdir -p "$WORK/anc/child"
eb_clone "$WORK/anc/child" anc-child
# The ancestor is untouched by its child's clone.
[ -d "$WORK/anc/.be" ] || _fail "anc-child: the ancestor store vanished"

pass
