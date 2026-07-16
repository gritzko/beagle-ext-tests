#!/bin/sh
# test/sub/pagercross — BE-039: pager put/delete crossing a sub mount.  A pager
# `:put <sub-crossing> <rest…>` composed the nav context (`//NAME`) onto ARG0
# ONLY; authorityRepo then anchored `repo` on the FILE path and climbed to the
# SUB, so raw rest args resolved in the wrong tree (arg0 staged sub-relative +
# unprefixed; the rest skipped "does not exist") — and DELETE silently removed
# the SUB's own file (destructive mis-target).  The fix: a VERB word-call keeps
# every arg RAW, the context travels as CONTEXT (driveSpell reentry), and put/
# delete resolve each arg against the CORRECT tree — byte-identical to the CLI:
#   * PUT descends the mount per-arg (stageInSub) → BOTH files staged in the sub.
#   * DELETE descends too (SUBS-039/DELETE, the put twin — was a DELDIRTY
#     refusal pre-delegation): both named files unlink, rows in the SUB wtlog.
# Builds par -> vendor/sub via the DIS-058 harness, clones it, then drives the
# put + delete arms in-process through the SHARED composer + driveSpell reentry.
. "$(dirname "$0")/../lib/subcase.sh"
. "$_ROOT/lib/golden.sh"                          # golden_assert
GOLDEN=${GOLDEN:-$_CASE/golden.out}

sc_build_parent                                   # par -> vendor/sub (gitlink)

D="$WORK/cli"
sc_jget "$D" "file://$PARSTORE/.be" >/dev/null
[ -f "$D/vendor/sub/lib.c" ] || _fail "sub not mounted at $D/vendor/sub"

# Two NEW untracked files inside the mounted sub, crossing the mount from the top.
mkdir -p "$D/vendor/sub/x"
for f in k l; do echo "$f payload" > "$D/vendor/sub/x/$f.txt"; done

# `//NAME` (SRC_ROOT-relative) must name the cloned wt for the nav context.
export SRC_ROOT="$WORK"
cp "$_CASE/drive.js" "$D/drive.js"; ln -sfn "$BEDIR" "$D/jsrc"

cd "$D"
"$JABC" ./drive.js 2>&1 | golden_assert "$NAME" "$GOLDEN"

# PUT staged BOTH files into the SUB's own wtlog (full top-relative prefix); the
# rest arg is no longer mis-resolved as "does not exist".
grep -qE 'put[[:space:]]+x/k\.txt' "$D/vendor/sub/.be" \
    || _fail "k.txt not staged in sub wtlog: $(cat "$D/vendor/sub/.be")"
grep -qE 'put[[:space:]]+x/l\.txt' "$D/vendor/sub/.be" \
    || _fail "l.txt (the rest arg) not staged in sub wtlog: $(cat "$D/vendor/sub/.be")"

# DELETE delegates (SUBS-039/DELETE, like the CLI): both named files unlink
# with `delete` rows in the SUB's own wtlog — correctly targeted, no parent leak.
grep -qE 'delete[[:space:]]+x/k\.txt' "$D/vendor/sub/.be" \
    || _fail "k.txt delete row not in the sub wtlog: $(cat "$D/vendor/sub/.be")"
grep -qE 'delete[[:space:]]+x/l\.txt' "$D/vendor/sub/.be" \
    || _fail "l.txt delete row not in the sub wtlog: $(cat "$D/vendor/sub/.be")"
[ -f "$D/vendor/sub/x/k.txt" ] && _fail "k.txt not unlinked by the cross-mount delete"
[ -f "$D/vendor/sub/x/l.txt" ] && _fail "l.txt not unlinked by the cross-mount delete"
grep -qE 'delete' "$D/.be" && _fail "delete row leaked into the parent wtlog"

echo "ok   pager cross-mount put + delete both delegate into the sub"
pass
