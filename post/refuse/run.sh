#!/bin/sh
# test/js/post/refuse — `bin/post.js` refuse paths (JS-051 FF-or-refuse).
# RULING 2026-07-16: a refusal is plain text, 1 line <=64 chars, no code prefix:
#   * empty-commit   → "no changes since base"       (no store write, rc != 0)
#   * non-FF advance → "can not be fast-forwarded"   (`?branch` diverged, fork)
# Each refusal must leave the worktree byte-intact (the post is all-or-nothing).
# DIS-076: a bare `#msg` commit is WT-only now and never hits a ref-based FF
# gate (see post.js's own comment: "the old commit-time [non-FF] gate ... is
# gone — that FF check now lives solely in advanceBranch's explicit arm"), so
# the non-FF refusal is only reachable via an explicit `?branch` advance whose
# target has GENUINELY diverged from cur (two forks off one base — the
# test/post/commit-diverged shape; a target merely CONTAINING cur is the
# "already contains cur's tip" class instead, see post/adv-contains).
. "$(dirname "$0")/../../lib/postcase.sh"

# the wt's current cur (base) tip via wtlog.curTip() — the WORKTREE hash.
_tip() {
    cat > "$WORK/.tip.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
const c=wtlog.open(info).curTip();
const u=utf8.Encode(((c&&c.sha)||"")+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.tip.js" "$1" "$BEDIR" 2>/dev/null
}

# DIS-076: a bare post never mints a ref — pin clones at ORG's own cur tip.
_orgtip() { ( cd "$1" && "$JABC" refs 2>/dev/null ) | sed -n 's/^cur: *//p'; }

# Origin store: post c1.
ORG="$WORK/org"; mkdir -p "$ORG"; ( cd "$ORG" && mkdir .be && {
    printf 'A\n' > a.txt; printf 'B\n' > b.txt
    "$BE" post '#c1' >/dev/null 2>&1
} )
ORG_TIP=$(_orgtip "$ORG")

# --- empty commit: a clean clone with no staged change must refuse ---------
# TEST-003: jab-seeded store is unnamed-project, so clone bare `file://<store>`
# (no `?/org` selector — jab never mints a named `org` shard).
mkdir "$WORK/e"; ( cd "$WORK/e" && "$BE" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 )
E_TIP0=$(_tip "$WORK/e")
if ( cd "$WORK/e" && "$JABC" post '#noop' ) >"$WORK/e.out" 2>"$WORK/e.err"; then
    _fail "empty post did NOT refuse: $(cat "$WORK/e.out")"
fi
grep -q "no changes since base" "$WORK/e.err" \
    || _fail "empty post refused but not 'no changes since base': $(cat "$WORK/e.err")"
[ "$(_tip "$WORK/e")" = "$E_TIP0" ] || _fail "empty post mutated the worktree tip"

# --- non-FF: two sibling worktrees SHARE the origin store (redirect clones,
# `file://ORG/.be#pin`).  Y commits (a.txt) then explicitly PUBLISHES `?feat`
# at its own tip (advanceBranch, DIS-061's "standard advance").  X commits a
# DIFFERENT change (b.txt) off the SAME base — a GENUINE fork: feat's tip is
# not an ancestor of X's cur AND X's cur is not an ancestor of feat's tip.
# X's own `post ?feat` can neither FF nor is it already contained →
# "can not be fast-forwarded", no write, wt byte-intact. --------------------
mkdir "$WORK/x"; ( cd "$WORK/x" && "$BE" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 )
mkdir "$WORK/y"; ( cd "$WORK/y" && "$BE" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 )
( cd "$WORK/y" && printf 'A2\n' > a.txt && "$BE" put a.txt >/dev/null 2>&1 && \
  "$BE" post '#adv' >/dev/null 2>&1 && "$JABC" post '?feat' >/dev/null 2>&1 ) \
    || _fail "y: advance + publish ?feat failed"
# x forks off the SAME base with its OWN commit — cur and feat now diverge.
( cd "$WORK/x" && printf 'B2\n' > b.txt && "$BE" put b.txt >/dev/null 2>&1 && \
  "$BE" post '#fork' >/dev/null 2>&1 ) || _fail "x: fork commit failed"
X_TIP_BEFORE=$(_tip "$WORK/x")
[ -n "$X_TIP_BEFORE" ] && [ "$X_TIP_BEFORE" != "$ORG_TIP" ] \
    || _fail "x: fork commit did not advance cur"
X_SUM_BEFORE=$(cat "$WORK/x/a.txt" "$WORK/x/b.txt" | cksum)
if ( cd "$WORK/x" && "$JABC" post '?feat' ) >"$WORK/x.out" 2>"$WORK/x.err"; then
    _fail "non-FF post did NOT refuse: $(cat "$WORK/x.out")"
fi
grep -q "can not be fast-forwarded" "$WORK/x.err" \
    || _fail "non-FF post refused but not as non-FF: $(cat "$WORK/x.err")"
[ "$(_tip "$WORK/x")" = "$X_TIP_BEFORE" ] || _fail "non-FF post mutated the worktree tip"
[ "$(cat "$WORK/x/a.txt" "$WORK/x/b.txt" | cksum)" = "$X_SUM_BEFORE" ] \
    || _fail "non-FF refusal mutated the worktree files"

pass
