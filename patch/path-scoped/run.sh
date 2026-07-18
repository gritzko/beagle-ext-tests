#!/bin/sh
# PATCH spec 2026-07-17: RED until the path slot scopes the absorb (today
# `patch <path>?<ref>` silently IGNORES the path — patchscope.parseShape
# reads only the query, the WHOLE tree absorbs and a provenance row lands).
#
# test/patch/path-scoped — PATCH.mkd §Path-scoped: "a non-empty path slot
# scopes the absorption to those paths, but records no provenance"; "a
# path-scoped row carries the path but no &theirs slot, so POST emits no
# provenance header and counts zero commits".  Topology:
#
#       T0 ── T1          ← cur (trunk): T1 edits h.c (ours-only)
#         \
#          F1             ← ?feat: F1 edits BOTH f.c and g.c (g.c: line 2)
#
#  Leg A (clean wt) `patch g.c?feat`: land theirs bytes for g.c ONLY; leave
#  f.c at the base bytes; record NO absorbed-line origin; the next `post`
#  counts zero absorbed — a SINGLE-parent commit, no picked/foster.
#  Leg B (ours-DIRTY scoped path; RULING 2026-07-17 "weave!!"): the scoped
#  path carries uncommitted local edits DISJOINT from theirs' change — the
#  same 3-way WEAVE as whole-tree runs, scoped to the path: the file ends up
#  with BOTH edits, never a plain theirs-bytes overwrite; other diverged
#  paths still untouched, still no origin row.
. "$(dirname "$0")/../../lib/patchspec.sh"

ORG="$WORK/org"; mkdir -p "$ORG/.be"
cd "$ORG"
printf 'f base\n' > f.c
printf 'g1\ng2\ng3\ng4\ng5\n' > g.c
printf 'h base\n' > h.c
_boot 't0'; T0=$BOOT
_fork feat
_sw feat
printf 'f THEIRS\n' > f.c
printf 'g1\nG-THEIRS\ng3\ng4\ng5\n' > g.c
_ci 'F1 f+g' f.c g.c
F1=$(_tip)
_trunk
printf 'h OURS\n' > h.c; _ci 't1 h' h.c
T1=$(_tip)
cd /

# ---- leg A: clean wt — theirs bytes land for the scoped path only ----------
A="$WORK/a"; ps_clone "$A"
( cd "$A" && "$JABC" patch 'g.c?feat' ) > "$WORK/p.out" 2> "$WORK/p.err" \
    || _fail "path-scoped patch failed: $(cat "$WORK/p.err")"

_want='g1
G-THEIRS
g3
g4
g5'
[ "$(cat "$A/g.c")" = "$_want" ] \
    || _fail "scoped path g.c did not land theirs bytes: $(cat "$A/g.c")"
#  THE trap this case exists for: the path slot silently widening to the tree.
[ "$(cat "$A/f.c")" = "f base" ] \
    || { echo "--- stdout ---"; cat "$WORK/p.out"; \
         _fail "path slot IGNORED — out-of-scope f.c absorbed theirs: $(cat "$A/f.c")"; }
[ "$(cat "$A/h.c")" = "h OURS" ] || _fail "patch touched ours-only h.c"
#  No origin: a path-scoped row must carry no &theirs commit for POST to fold.
ps_patch_rows "$A" | grep -q "$F1" \
    && _fail "path-scoped patch recorded the line origin ($F1): $(ps_patch_rows "$A")" \
    || true

#  The next post counts ZERO absorbed commits: single parent, no headers.
( cd "$A" && "$JABC" post 'scoped absorb' ) > "$WORK/post.out" 2> "$WORK/post.err" \
    || _fail "post failed: $(cat "$WORK/post.err")"
ps_commit "$A" > "$WORK/commit.txt"
_pars=$(sed -n 's/^parent //p' "$WORK/commit.txt")
_np=$(printf '%s\n' "$_pars" | grep -cE '^[0-9a-f]{40}$')
[ "$_np" = "1" ] \
    || { cat "$WORK/commit.txt"; \
         _fail "post after a path-scoped patch grew $_np parents (origin leaked)"; }
[ "$_pars" = "$T1" ] || _fail "the single parent is not the old cur ($T1): $_pars"
! grep -qE '^(picked|foster) ' "$WORK/commit.txt" \
    || _fail "path-scoped absorb grew a provenance header: $(cat "$WORK/commit.txt")"
echo "ok   A: scoped bytes landed for g.c only, no origin, post counted zero absorbed"

# ---- leg B: ours-DIRTY scoped path — WEAVE, both edits land ("weave!!") ----
B="$WORK/b"; ps_clone "$B"
printf 'g1\ng2\ng3\ng4\nDIRTY-g5\n' > "$B/g.c"       # uncommitted, disjoint (l5)
( cd "$B" && "$JABC" patch 'g.c?feat' ) > "$WORK/pb.out" 2> "$WORK/pb.err" \
    || _fail "path-scoped patch over a dirty path failed: $(cat "$WORK/pb.err")"
_want='g1
G-THEIRS
g3
g4
DIRTY-g5'
[ "$(cat "$B/g.c")" = "$_want" ] \
    || _fail "dirty scoped path was not WEAVED (ruling: weave, no overwrite):
$(cat "$B/g.c")"
[ "$(cat "$B/f.c")" = "f base" ] \
    || { echo "--- stdout ---"; cat "$WORK/pb.out"; \
         _fail "path slot IGNORED (dirty leg) — out-of-scope f.c absorbed theirs: $(cat "$B/f.c")"; }
[ "$(cat "$B/h.c")" = "h OURS" ] || _fail "dirty-leg patch touched ours-only h.c"
ps_patch_rows "$B" | grep -q "$F1" \
    && _fail "dirty-leg path-scoped patch recorded the line origin ($F1): $(ps_patch_rows "$B")" \
    || true
echo "ok   B: dirty scoped path weave-merged BOTH edits, f.c untouched, no origin"

pass
