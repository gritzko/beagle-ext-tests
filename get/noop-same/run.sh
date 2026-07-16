#!/bin/sh
# test/get/noop-same — GET-047: HISTORY SAME (3.3) "nothing to do": at the
# tracked tip a bare `jab get` leaves every CONTENT file byte-identical (the
# `..be.idx` store sidecar may be minted — metadata, not content, same
# exclusion as getcase's tree_dump) and APPENDS exactly one wtlog `get` row
# re-pinning the SAME tip — the observed, stable record-keeping.
. "$(dirname "$0")/../../lib/getrepro.sh"

SRC=$(gr_src src)
TIP=$(gr_tip_sha "$SRC")
[ -n "$TIP" ] || _fail "no source tip"
gr_jclone "$SRC" "$WORK/jT"

# snap DIR — the recursive content-file listing + bytes (cksum), sans the .be
# store/wtlog, its ..be.idx sidecar and .git (the tree_dump exclusion set).
snap() {
    ( cd "$1" && find . -type f \
        | grep -vE '^\./(\.be(/|$)|\.\.be\.idx$|\.git/)' \
        | sort | while read -r _f; do cksum "$_f"; done )
}
snap "$WORK/jT" > "$WORK/before.snap"
PRE=$(gr_wtraw "$WORK/jT")

rc=$(gr_jget "$WORK/jT")
[ "$rc" = 0 ] || { cat "$WORK/last.err"; _fail "bare get exit=$rc"; }

snap "$WORK/jT" > "$WORK/after.snap"
cmp -s "$WORK/before.snap" "$WORK/after.snap" || {
    diff "$WORK/before.snap" "$WORK/after.snap" >&2 || true
    _fail "bare get at the tracked tip CHANGED the worktree"; }

# The wtlog is append-only: the old log intact, plus EXACTLY one new `get`
# row re-pinning the SAME tip (no drift to another sha, no track rewrite).
POST=$(gr_wtraw "$WORK/jT")
case "$POST" in "$PRE"*) ;; *) _fail "wtlog not append-only across a no-op get";; esac
TAIL=${POST#"$PRE"}
printf '%s\n' "$TAIL" | grep -q "get?#$TIP\$" \
    || { echo "--- appended: [$TAIL]" >&2; _fail "no-op row is not get?#<same tip>"; }
[ "$(printf '%s\n' "$TAIL" | awk -F'get' '{print NF-1}')" = 1 ] \
    || { echo "--- appended: [$TAIL]" >&2; _fail "more than one row appended by a no-op get"; }

pass
