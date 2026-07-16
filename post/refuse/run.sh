#!/bin/sh
# test/js/post/refuse — `bin/post.js` refuse paths (JS-051 FF-or-refuse):
#   * empty-commit   → POSTNONE  (no store write, non-zero exit)
#   * non-FF advance → POSTNOFF  (an explicit `?branch` target diverged from cur)
# Each refusal must leave the worktree byte-intact (the post is all-or-nothing).
# DIS-076: a bare `#msg` commit is WT-only now and never hits a ref-based FF
# gate (see post.js's own comment: "the old commit-time POSTNOFF gate ... is
# gone — that FF check now lives solely in advanceBranch's explicit arm"), so
# POSTNOFF is only reachable via an explicit `?branch` advance whose target
# has diverged from cur — reproduced below with a real branch divergence.
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

# --- empty commit: a clean clone with no staged change must POSTNONE -------
# TEST-003: jab-seeded store is unnamed-project, so clone bare `file://<store>`
# (no `?/org` selector — jab never mints a named `org` shard).
mkdir "$WORK/e"; ( cd "$WORK/e" && "$BE" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 )
E_TIP0=$(_tip "$WORK/e")
if ( cd "$WORK/e" && "$JABC" post '#noop' ) >"$WORK/e.out" 2>"$WORK/e.err"; then
    _fail "empty post did NOT refuse (expected POSTNONE): $(cat "$WORK/e.out")"
fi
grep -q POSTNONE "$WORK/e.err" || _fail "empty post refused but not via POSTNONE: $(cat "$WORK/e.err")"
[ "$(_tip "$WORK/e")" = "$E_TIP0" ] || _fail "empty post mutated the worktree tip"

# --- non-FF: two sibling worktrees SHARE the origin store (redirect clones,
# `file://ORG/.be#pin`); Y commits then explicitly PUBLISHES `?feat` at its own
# tip (advanceBranch, DIS-061's "standard advance") — feat now diverges from
# X, which never advanced past ORG_TIP.  X's own `post ?feat` cannot FF (feat's
# tip is not an ancestor of X's cur) → POSTNOFF, no write. ------------------
mkdir "$WORK/x"; ( cd "$WORK/x" && "$BE" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 )
mkdir "$WORK/y"; ( cd "$WORK/y" && "$BE" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 )
( cd "$WORK/y" && printf 'A2\n' > a.txt && "$BE" put a.txt >/dev/null 2>&1 && \
  "$BE" post '#adv' >/dev/null 2>&1 && "$JABC" post '?feat' >/dev/null 2>&1 ) \
    || _fail "y: advance + publish ?feat failed"
# x's own cur is still parented at ORG_TIP — unrelated to feat's now-diverged tip.
X_TIP_BEFORE=$(_tip "$WORK/x")
if ( cd "$WORK/x" && "$JABC" post '?feat' ) >"$WORK/x.out" 2>"$WORK/x.err"; then
    _fail "non-FF post did NOT refuse (expected POSTNOFF): $(cat "$WORK/x.out")"
fi
grep -q POSTNOFF "$WORK/x.err" || _fail "non-FF post refused but not via POSTNOFF: $(cat "$WORK/x.err")"
[ "$(_tip "$WORK/x")" = "$X_TIP_BEFORE" ] || _fail "non-FF post mutated the worktree tip"

pass
