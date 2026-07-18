#!/bin/sh
# PATCH spec 2026-07-17: RED until `picked` provenance lands (cherry `#hash`
# becomes a MERGE PARENT today, no `picked` header, and a re-pick is not
# deduped — post.js/fold-commit.js: "single-parent + no foster/picked").
#
# test/patch/provenance-picked — PATCH.mkd §Shapes/§Ancestor-skip: "`#<hash>`
# cherry-pick: absorb the one named commit; recorded as `picked`, NEVER a
# parent"; "`picked` headers are dedup-only and do not participate in
# reachability".  Topology:
#
#       T0 ── T1                    ← cur (trunk): T1 edits line 5
#         \
#          F1 ── F2 ── F3           ← ?feat: edits line 2, 3, 4 (one each)
#
#  leg A `patch #F2` + `post`: the commit carries EXACTLY ONE parent (the old
#        cur) and a `picked <F2>` header — git-visible history stays linear.
#  leg B re-`patch #F2`: dedup no-op — no new patch row.
#  leg C `patch ?feat` after the pick: the picked sha is NOT reachability —
#        the line absorb still sees every missing feat commit (F1+F3's edits
#        land; F2's are already in the wt bytes).
. "$(dirname "$0")/../../lib/patchspec.sh"

ORG="$WORK/org"; mkdir -p "$ORG/.be"
cd "$ORG"
printf 'l1\nl2\nl3\nl4\nl5\n' > f.txt
_boot 't0'; T0=$BOOT
_fork feat
_sw feat
printf 'l1\nF-l2\nl3\nl4\nl5\n' > f.txt;       _ci 'F1 l2' f.txt
F1=$(_tip)
printf 'l1\nF-l2\nF-l3\nl4\nl5\n' > f.txt;     _ci 'F2 l3' f.txt
F2=$(_tip)
printf 'l1\nF-l2\nF-l3\nF-l4\nl5\n' > f.txt;   _ci 'F3 l4' f.txt
F3=$(_tip)
_trunk
printf 'l1\nl2\nl3\nl4\nT-l5\n' > f.txt;       _ci 't1 l5' f.txt
T1=$(_tip)
cd /

A="$WORK/a"; ps_clone "$A"

# ---- leg A: cherry + post → single parent + `picked <F2>` ------------------
( cd "$A" && "$JABC" patch "#$F2" ) > "$WORK/p.out" 2> "$WORK/p.err" \
    || _fail "patch #F2 failed: $(cat "$WORK/p.err")"
( cd "$A" && "$JABC" post 'pick F2' ) > "$WORK/post.out" 2> "$WORK/post.err" \
    || _fail "post failed: $(cat "$WORK/post.err")"
ps_commit "$A" > "$WORK/commit.txt"
_pars=$(sed -n 's/^parent //p' "$WORK/commit.txt")
_np=$(printf '%s\n' "$_pars" | grep -cE '^[0-9a-f]{40}$')
[ "$_np" = "1" ] \
    || { cat "$WORK/commit.txt"; \
         _fail "a cherry must NOT be a merge — $_np parents (theirs rode as a parent)"; }
[ "$_pars" = "$T1" ] || _fail "the single parent is not the old cur ($T1): $_pars"
grep -q "^picked $F2\$" "$WORK/commit.txt" \
    || { cat "$WORK/commit.txt"; _fail "no 'picked $F2' header on the pick commit"; }
echo "ok   A: pick commit = single parent (old cur) + picked $F2"

# ---- leg B: re-pick the same #F2 → dedup no-op (no new row) ----------------
_rows0=$(ps_patch_rows "$A" | wc -l)
( cd "$A" && "$JABC" patch "#$F2" ) > "$WORK/p2.out" 2> "$WORK/p2.err" \
    || _fail "re-patch #F2 exited non-zero: $(cat "$WORK/p2.err")"
_rows1=$(ps_patch_rows "$A" | wc -l)
[ "$_rows1" = "$_rows0" ] \
    || _fail "re-picking an already-picked sha appended a row (dedup broken):
$(ps_patch_rows "$A")"
echo "ok   B: re-pick of $F2 is a dedup no-op"

# ---- leg C: picked is NOT reachability — ?feat still absorbs the line ------
( cd "$A" && "$JABC" patch '?feat' ) > "$WORK/p3.out" 2> "$WORK/p3.err" \
    || _fail "patch ?feat after the pick failed: $(cat "$WORK/p3.err")"
_want='l1
F-l2
F-l3
F-l4
T-l5'
[ "$(cat "$A/f.txt")" = "$_want" ] \
    || _fail "?feat after a pick lost commits (picked leaked into reachability?):
$(cat "$A/f.txt")"
echo "ok   C: the later ?feat line absorb still sees commits past the pick"

pass
