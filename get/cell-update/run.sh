#!/bin/sh
# test/get/cell-update — GET-047: `jab get '//X/'` in an ESTABLISHED wt whose
# store DIFFERS from //X's is a cross-source UPDATE (GET.mkd 1.3 x 2.1), not a
# re-clone: fetch //X's objects into the wt's OWN shard, weave the dirty edit,
# keep the staged put row, and RE-TIE the last get record to `//X#<new base>`.
# The GETCELL refusal stays for a target sharing NO ancestry with the cell's
# cur (the true double-clone shape): loud, non-zero, wt + wtlog byte-identical.
#
# The live shape (work/JAB-008): W sits under the project root's work/ but is
# anchored on an EXTERNAL store A; //src carries the SAME project at c2 in its
# own newer store.  RED before the fix: the update leg refuses with GETCELL.
. "$(dirname "$0")/../../lib/getrepro.sh"

# URI-016: bound the `//X` project-root climb at this case's scratch (ctest's
# own $BE_ROOT sits higher and sees unrelated anchors) — the wt-operand pattern.
export BE_ROOT="$WORK"

# --- the project root (the journal-analog, its own unrelated store) --------
PROJ="$WORK/proj"
mkdir -p "$PROJ/.be" "$PROJ/work"
printf 'root\n' > "$PROJ/root.txt"
( cd "$PROJ" && "$JABC" post 'root' ) >/dev/null 2>&1 || _fail "seed PROJ failed"

# --- store A: an EXTERNAL colocated primary with the project at c1 ----------
STOREA="$WORK/storeA"
mkdir -p "$STOREA/.be"
printf 'l1\nl2\nl3\nl4\nl5\n' > "$STOREA/readme.txt"
( cd "$STOREA" && "$JABC" post 'c1' ) >/dev/null 2>&1 || _fail "seed store A failed"
C1=$(gr_tip_sha "$STOREA")
[ -n "$C1" ] || _fail "no c1 tip"

# W: an ESTABLISHED cell under work/, anchored on store A (the JAB-008 shape).
W="$PROJ/work/w"
mkdir -p "$W"
( cd "$W" && "$JABC" get "file://$STOREA/.be#$C1" ) >/dev/null 2>&1 \
    || _fail "clone W failed"

# --- `//src`: the SAME project at c2, in its OWN (different) store ----------
SRC="$PROJ/work/src"
mkdir -p "$SRC"
cp -R "$STOREA/.be" "$SRC/.be"
printf 'l1\nl2\nl3\nl4\nl5-new\n' > "$SRC/readme.txt"
printf 'T2\n' > "$SRC/t2.txt"
( cd "$SRC" && "$JABC" put readme.txt t2.txt && "$JABC" post 'c2' ) >/dev/null 2>&1 \
    || _fail "advance SRC (c2) failed"
C2=$(gr_tip_sha "$SRC")
[ -n "$C2" ] && [ "$C2" != "$C1" ] || _fail "SRC did not advance past c1"

# --- W: a dirty edit + a staged put ----------------------------------------
printf 'l1-dirty\nl2\nl3\nl4\nl5\n' > "$W/readme.txt"
printf 'S\n' > "$W/staged.txt"
( cd "$W" && "$JABC" put staged.txt ) >/dev/null 2>&1 || _fail "put staged.txt failed"

# --- the cross-source UPDATE: `get '//src/'` (RED: GETCELL refuses this) ---
rc=$(gr_jget "$W" '//src/')
[ "$rc" = 0 ] || { cat "$WORK/last.err" >&2; _fail "get //src/ exit=$rc (GETCELL?)"; }

# c2's new file landed.
gr_file_is "$W/t2.txt" "T2"
# the dirty head-edit is WEAVED with c2's tail-edit (mode 2.1, never clobbered).
gr_file_is "$W/readme.txt" "l1-dirty
l2
l3
l4
l5-new"
# the staged put row survives the update (and the staged file is untouched).
gr_file_is "$W/staged.txt" "S"
gr_wtlog_has "$W" "put[^#]*staged.txt"
# the wt RE-TIES to the target: the last get record is now `//src/#<c2>`.
gr_wtlog_has "$W" "//src/?#$C2"
_LAST_GET=$(gr_wtraw "$W" | grep -oE "get[^ ]*#[0-9a-f]{40}" | tail -1)
printf '%s\n' "$_LAST_GET" | grep -qE "//src/?#$C2" \
    || _fail "recentmost get record is not the //src tie: $_LAST_GET"

# the FETCH LEG wrote c2's objects into W's OWN store A: with //src's store
# gone, W still reads its whole baseline (no TRACKED path degrades to unk;
# a pending put crossing a get boundary reads unk on EVERY update pattern).
mv "$SRC/.be" "$WORK/src.be.bak"
( cd "$W" && "$JABC" status ) >"$WORK/st.out" 2>"$WORK/st.err" \
    || { cat "$WORK/st.err" >&2; _fail "status after the update failed"; }
# BRO-030 quad default: an unresolved baseline would read untracked `...o`; the
# woven dirty edit reads `...v`.
grep -qE '\.\.\.o (readme|t2)' "$WORK/st.out" \
    && _fail "baseline unreadable from store A — objects were not fetched" || true
grep -qE '\.\.\.v readme\.txt' "$WORK/st.out" \
    || _fail "the woven dirty edit does not read as a local ...v: $(cat "$WORK/st.out")"
mv "$WORK/src.be.bak" "$SRC/.be"

# --- SUB leg: a worktree source's sub mounts via the COMPOSED wt URI -------
# GET-047 ruling: //src's sub IS the worktree //src/dog — its own anchor names
# the backing store; the declared https url must NEVER be contacted.
SUBSTORE="$WORK/storeS"
mkdir -p "$SUBSTORE/.be"
printf 'sub payload\n' > "$SUBSTORE/S.c"
( cd "$SUBSTORE" && "$JABC" post 'sub initial' ) >/dev/null 2>&1 \
    || _fail "seed SUBSTORE failed"
SPIN=$(gr_tip_sha "$SUBSTORE")
[ -n "$SPIN" ] || _fail "no sub pin"

mkdir -p "$SRC/dog"
( cd "$SRC/dog" && "$JABC" get "file://$SUBSTORE/.be#$SPIN" ) >/dev/null 2>&1 \
    || _fail "mount SRC/dog failed"
printf '[submodule "dog"]\n\tpath = dog\n\turl = https://127.0.0.1:1/dog.git\n' \
    > "$SRC/.gitmodules"
# the gitlink pin row (no CLI spelling for a raw pin — the gitlink-fork idiom).
cat > "$WORK/.pinrow.js" <<'EOF'
const ulog = require(process.argv[2] + "/shared/ulog.js");
ulog.append(process.argv[4], [{ verb: "put",
  uri: URI.make(undefined, undefined, process.argv[3], undefined, process.argv[5]) }]);
EOF
( cd "$SRC" && "$JABC" put .gitmodules ) >/dev/null 2>&1 || _fail "put .gitmodules failed"
"$JABC" "$WORK/.pinrow.js" "$BEDIR" "dog" "$SRC/.be/wtlog" "$SPIN" >/dev/null 2>&1 || true
( cd "$SRC" && "$JABC" post 'c3 sub' ) >/dev/null 2>&1 || _fail "post c3 failed"
C3=$(gr_tip_sha "$SRC")
[ -n "$C3" ] && [ "$C3" != "$C2" ] || _fail "SRC did not advance to c3"

rc=$(gr_jget "$W" '//src/')
[ "$rc" = 0 ] || { cat "$WORK/last.err" >&2; _fail "get //src/ (sub leg) exit=$rc"; }
grep -qE "SUBFETCH|127\.0\.0\.1" "$WORK/last.err" "$WORK/last.out" 2>/dev/null \
    && _fail "the https url was attempted for a worktree source" || true
gr_file_is "$W/dog/S.c" "sub payload"
[ -e "$W/dog/.be" ] || _fail "no sub anchor at W/dog"
# the sub anchors the COMPOSED worktree's own backing store, never the url.
od -An -c "$W/dog/.be" | tr -d ' \n' | grep -q "storeS/.be" \
    || _fail "W/dog does not anchor the sub worktree's backing store: $(cat "$W/dog/.be")"
gr_wtlog_has "$W" "//src/?#$C3"

# --- refusal leg: an UNRELATED same-named project refuses loudly -----------
ROGUE="$PROJ/work/rogue"
mkdir -p "$ROGUE/.be"
printf 'X\n' > "$ROGUE/x.txt"
( cd "$ROGUE" && "$JABC" post 'rogue c1' ) >/dev/null 2>&1 || _fail "seed ROGUE failed"
RTIP=$(gr_tip_sha "$ROGUE")

cp "$W/.be" "$WORK/w.be.before"
rc=$(gr_jget "$W" '//rogue/')
[ "$rc" != 0 ] || _fail "get //rogue/ (unrelated history) did NOT refuse"
grep -q "GETCELL" "$WORK/last.err" "$WORK/last.out" 2>/dev/null \
    || _fail "no GETCELL refusal for the unrelated target: $(cat "$WORK/last.err")"
# the one-liner names BOTH tips (the cell's cur and the refused target's).
grep -q "$C3" "$WORK/last.err" || _fail "refusal does not name the cur tip $C3"
grep -q "$RTIP" "$WORK/last.err" || _fail "refusal does not name the target tip $RTIP"
cmp -s "$W/.be" "$WORK/w.be.before" || _fail "refused get MUTATED W's wtlog"
gr_file_is "$W/readme.txt" "l1-dirty
l2
l3
l4
l5-new"
gr_file_is "$W/t2.txt" "T2"
[ ! -e "$W/x.txt" ] || _fail "refused get landed rogue files"

pass
