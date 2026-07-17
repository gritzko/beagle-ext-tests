#!/bin/sh
# test/sub/stagedsub — STATUS-007: `jab status` must STILL recurse into a
# mounted submodule whose gitlink bump is STAGED in the parent.  classify
# routes a staged full-sha gitlink out as a `put` row (it never reaches
# res.gitlinks), so the old recursion gate (`byPath[subPath]` presence)
# skipped the sub SILENTLY — the sub went invisible exactly while it had
# staged changes worth seeing.  Fixture mirrors advput: build parent+sub,
# clone, advance the sub, stage the bump via `put vendor/sub` (BE-049),
# then dirty the sub and assert the parent status still emits the sub's
# `status vendor/sub` section with its rows.
. "$(dirname "$0")/../lib/subcase.sh"

sc_build_parent                                   # par -> vendor/sub (gitlink)

WORKD=$(rs_work_root "$WORK")
D="$WORKD/cli"
sc_jget "$D" "file://$PARSTORE/.be" >/dev/null
[ -f "$D/vendor/sub/lib.c" ] || _fail "sub not mounted at $D/vendor/sub"

# ADVANCE the sub: a new sub commit, tip descends the parent's gitlink pin.
( cd "$D/vendor/sub" && printf 'sub payload v2\n' > lib.c \
    && "$JABC" post '#advance sub' ) >/dev/null 2>&1 || _fail "advance sub post"
SUBTIP=$(sc_subtip "$D/vendor/sub"); sc_is40 "$SUBTIP" "advanced sub tip"
PIN0=$(sc_gitlink_pin "$D" "vendor/sub"); sc_is40 "$PIN0" "gitlink pin"
[ "$SUBTIP" != "$PIN0" ] || _fail "sub did not advance (tip == pin)"

# STAGE the gitlink bump in the parent (BE-049: `put <sub>` records the bump).
( cd "$D" && "$JABC" put vendor/sub ) >/dev/null 2>&1 || _fail "put vendor/sub"
grep -qE "put[[:space:]]+vendor/sub#$SUBTIP" "$D/.be" \
    || _fail "gitlink bump not staged in the parent wtlog: $(tail -4 "$D/.be")"

# Dirty the sub AFTER the bump so its status section has rows worth seeing.
printf 'sub helper EDITED\n' > "$D/vendor/sub/helper.c"       # sub mod
echo "u payload" > "$D/vendor/sub/u.txt"                      # sub unk

# `jab status` in the parent MUST print the staged `put vendor/sub` row
# (unchanged) AND still recurse: the sub's own `status vendor/sub` hunk,
# carrying the sub's mod/unk rows path-prefixed under vendor/sub/.
ST=$(cd "$D" && "$JABC" status --plain 2>&1)
printf '%s\n' "$ST"
# BRO-030 quad default: parent staged gitlink bump `...V`; sub edit `...v`; sub
# untracked `...o`; the recursion banner `status vendor/sub` is unchanged.
printf '%s\n' "$ST" | grep -qE '\.\.\.V[[:space:]]+vendor/sub' \
    || _fail "parent staged ...V row missing: $ST"
printf '%s\n' "$ST" | grep -q '^status vendor/sub$' \
    || _fail "staged sub's status section missing (silent skip): $ST"
printf '%s\n' "$ST" | grep -qE '\.\.\.v[[:space:]]+vendor/sub/helper\.c' \
    || _fail "sub ...v row missing from the sub section: $ST"
printf '%s\n' "$ST" | grep -qE '\.\.\.o[[:space:]]+vendor/sub/u\.txt' \
    || _fail "sub ...o row missing from the sub section: $ST"

echo "ok   staged-bump sub still emits its status section (rows + banner)"
pass
