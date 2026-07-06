#!/bin/sh
# test/type/change — entry TYPE-CHANGE replication (GET-039 follow-up).
#
# For EVERY ordered pair of {file,dir,link}: commit `item` as type FROM (v1),
# clone it (the OLD clone), then in a WORK clone change `item` to type TO and
# `jab put`+`jab post` (v2).  Assert the new type replicates THREE ways:
#   1. a FRESH clone of v2 materialises TO,
#   2. (the new part) UPDATING the OLD v1 clone with `jab get` flips its on-disk
#      entry type FROM->TO in place (the harder case — get must drop a stale dir
#      to write a file/link, or vice versa).
# RED where a baseline type shadows the new one; GREEN when every transition
# round-trips on both fresh-clone AND in-place-update.
# TEST-003: project-less local `file://` clone (no keeper); single project, no sub.
. "$(dirname "$0")/../../sub/lib/subcase.sh"

X=item                       # the path whose entry type changes
LINKTGT=some/target          # a relative symlink target (a 120000 blob's bytes)

# --- make `item` (arg $1) as a given type, in cwd ---------------------------
mk_file() { rm -rf "$1"; printf 'file payload\n' > "$1"; }
mk_dir()  { rm -rf "$1"; mkdir -p "$1"; printf 'inner payload\n' > "$1/inner.txt"; }
mk_link() { rm -rf "$1"; ln -s "$LINKTGT" "$1"; }

# --- assert `item` (arg $1) is a given type: echo "" if ok, else the reason --
why_file() { { [ -f "$1" ] && [ ! -L "$1" ]; } || echo "not a regular file"; }
why_dir()  { { [ -d "$1" ] && [ ! -L "$1" ]; } || echo "not a directory"; }
why_link() { [ -L "$1" ] || echo "not a symlink"; }

FAILS=""

one() {                      # one FROM TO
    FROM=$1; TO=$2; tag="$FROM->$TO"; PROJ="$FROM-$TO"
    S="$WORK/$PROJ"; rm -rf "$S"; mkdir -p "$S/.be"

    # v1: commit `item` as FROM (+ a stable anchor file so the store is non-empty)
    ( cd "$S"; printf 'keep\n' > keep.txt; mk_$FROM "$X"; "$BE" post "#$tag v1" ) \
        >/dev/null 2>&1 || { FAILS="$FAILS $tag(setup)"; return; }

    # the OLD clone — sits at v1 until we update it with `jab get` at the end
    TOLD="$S/old"
    [ "$(sc_jget "$TOLD" "file://$S/.be")" = 0 ] \
        || { FAILS="$FAILS $tag(get-old)"; return; }
    r=$(why_$FROM "$TOLD/$X"); [ -z "$r" ] \
        || { FAILS="$FAILS $tag(old-v1:$r)"; return; }

    # v2: in a WORK clone, change `item` FROM->TO, then PUT + POST
    TW="$S/work"
    [ "$(sc_jget "$TW" "file://$S/.be")" = 0 ] \
        || { FAILS="$FAILS $tag(get-work)"; return; }
    ( cd "$TW"; mk_$TO "$X" ) || { FAILS="$FAILS $tag(edit)"; return; }
    ( cd "$TW" && "$JABC" put "$X" ) >"$WORK/.put" 2>&1 || true
    _rc=0; ( cd "$TW" && "$JABC" post "#$tag v2" ) >"$WORK/.post" 2>&1 || _rc=$?
    [ "$_rc" = 0 ] || { FAILS="$FAILS $tag(post:$_rc)"; return; }

    # 1. FRESH clone of v2 — the new type must materialise
    TNEW="$S/new"
    [ "$(sc_jget "$TNEW" "file://$TW/.be")" = 0 ] \
        || { FAILS="$FAILS $tag(get-new)"; return; }
    r=$(why_$TO "$TNEW/$X"); [ -z "$r" ] \
        || { FAILS="$FAILS $tag(new:$r)"; return; }

    # 2. NEW PART: UPDATE the OLD v1 clone with `jab get` — its on-disk entry
    #    type must flip FROM->TO in place (get drops the stale dir / leaf).
    _rc=0; ( cd "$TOLD" && "$JABC" get "file://$TW/.be" ) >"$WORK/.upd" 2>&1 || _rc=$?
    [ "$_rc" = 0 ] || { FAILS="$FAILS $tag(update:$_rc)"; return; }
    r=$(why_$TO "$TOLD/$X"); [ -z "$r" ] \
        || { FAILS="$FAILS $tag(updated-old:$r)"; return; }

    echo "ok   $tag — fresh clone AND updated old clone both replicate $TO"
}

for pair in file:dir file:link dir:file dir:link link:file link:dir; do
    one "${pair%:*}" "${pair#*:}"
done

[ -z "$FAILS" ] || _fail "type-change transitions failed:$FAILS"
pass
