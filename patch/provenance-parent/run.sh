#!/bin/sh
# test/patch/provenance-parent — PATCH.mkd 2026-07-17 §Shapes: "`?<ref>`:
# absorb every missing commit of that line; the next POST records the ref as
# a NON-FIRST `parent`".  Topology:
#
#       T0 ── T1          ← cur (trunk): T1 edits line 1
#         \
#          F1             ← ?feat: F1 edits line 3 (disjoint)
#
#  `patch ?feat` then `post`: the landed commit must be a REAL merge —
#  EXACTLY two parents, the FIRST the old cur (T1), the SECOND (non-first)
#  the absorbed line tip (F1) — and carry NO picked/foster headers (those
#  belong to the `#hash` / `patch!` shapes).
#
#  GREEN today: post.js folds each in-scope patch row's theirs sha into the
#  commit's parents after the cur-tip first parent (DIS-057 ruling).
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
( cd "$A" && "$JABC" patch '?feat' ) > "$WORK/p.out" 2> "$WORK/p.err" \
    || _fail "patch ?feat failed: $(cat "$WORK/p.err")"
( cd "$A" && "$JABC" post 'absorb feat' ) > "$WORK/post.out" 2> "$WORK/post.err" \
    || _fail "post failed: $(cat "$WORK/post.err")"

ps_commit "$A" > "$WORK/commit.txt"
_pars=$(sed -n 's/^parent //p' "$WORK/commit.txt")
_np=$(printf '%s\n' "$_pars" | grep -cE '^[0-9a-f]{40}$')
[ "$_np" = "2" ] \
    || { cat "$WORK/commit.txt"; _fail "absorb commit has $_np parents, want exactly 2"; }
[ "$(printf '%s\n' "$_pars" | sed -n 1p)" = "$T1" ] \
    || _fail "FIRST parent is not the old cur ($T1): $_pars"
[ "$(printf '%s\n' "$_pars" | sed -n 2p)" = "$F1" ] \
    || _fail "the absorbed ref tip ($F1) is not the NON-FIRST parent: $_pars"
! grep -qE '^(picked|foster) ' "$WORK/commit.txt" \
    || _fail "a plain ?ref absorb grew a picked/foster header: $(cat "$WORK/commit.txt")"
echo "ok   merge commit: first parent = old cur, exactly one theirs parent = $F1"

pass
