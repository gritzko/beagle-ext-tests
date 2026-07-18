#!/bin/sh
# PATCH spec 2026-07-17: RED until `foster` provenance lands (the `patch!`
# verb bang folds to --force today and the absorb still posts a 2-parent
# merge; fold-commit.js: "single-parent + no foster/picked").
#
# test/patch/provenance-foster — PATCH.mkd §Shapes/§Merge base: "`patch!
# ?<ref>`: same absorption, origin recorded as a `foster` header git does not
# understand — the fostered object is not propagated, a local reference
# only"; "foster keeps the same weave but hides the link from git — the
# landed history reads linear, the rebase flavor".  Topology:
#
#       T0 ── T1          ← cur (trunk): T1 edits line 1
#         \
#          F1             ← ?feat: F1 edits line 3 (disjoint)
#
#  `patch! ?feat` then `post`: the commit must carry EXACTLY ONE git-visible
#  `parent` (the old cur) plus a `foster <F1>` header — never a second parent.
. "$(dirname "$0")/../../lib/patchspec.sh"

ORG="$WORK/org"; mkdir -p "$ORG/.be"
cd "$ORG"
printf 'l1\nl2\nl3\nl4\nl5\n' > f.txt
_boot 't0'; T0=$BOOT
_fork feat
_sw feat
printf 'l1\nl2\nF-l3\nl4\nl5\n' > f.txt; _ci 'F1 l3' f.txt
F1=$(_tip)
_trunk
printf 'T-l1\nl2\nl3\nl4\nl5\n' > f.txt; _ci 't1 l1' f.txt
T1=$(_tip)
cd /

A="$WORK/a"; ps_clone "$A"
( cd "$A" && "$JABC" 'patch!' '?feat' ) > "$WORK/p.out" 2> "$WORK/p.err" \
    || _fail "patch! ?feat failed: $(cat "$WORK/p.err")"
#  The absorption itself is the same as plain patch — theirs' edit landed.
grep -q 'F-l3' "$A/f.txt" || _fail "patch! absorbed nothing: $(cat "$A/f.txt")"
( cd "$A" && "$JABC" post 'foster feat' ) > "$WORK/post.out" 2> "$WORK/post.err" \
    || _fail "post failed: $(cat "$WORK/post.err")"

ps_commit "$A" > "$WORK/commit.txt"
_pars=$(sed -n 's/^parent //p' "$WORK/commit.txt")
_np=$(printf '%s\n' "$_pars" | grep -cE '^[0-9a-f]{40}$')
[ "$_np" = "1" ] \
    || { cat "$WORK/commit.txt"; \
         _fail "patch! must stay git-linear — $_np parents (theirs rode as a parent)"; }
[ "$_pars" = "$T1" ] || _fail "the single parent is not the old cur ($T1): $_pars"
grep -q "^foster $F1\$" "$WORK/commit.txt" \
    || { cat "$WORK/commit.txt"; _fail "no 'foster $F1' header on the absorb commit"; }
echo "ok   foster commit: single git parent (old cur) + foster $F1"

pass
