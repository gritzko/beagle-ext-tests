#!/bin/sh
# test/js/post/conflict — `bin/post.js` POST-017 conflict pre-scan: a tracked
# `add` carrying a complete WEAVE conflict-marker triple must refuse with the
# plain "conflict marker in tracked file <path>" text (RULING 2026-07-16)
# BEFORE any store write, and `--force` overrides it.  A bare `<<<<` in prose
# (no `||||`/`>>>>` partners) is NOT a conflict and posts fine.
. "$(dirname "$0")/../../lib/postcase.sh"

# DIS-076: a commit advances the WORKTREE, never a ref (uniform ruling) — the
# wtlog cur tip is the only thing that moves, so probe THAT, not a store ref.
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

ORG="$WORK/org"; mkdir -p "$ORG"; ( cd "$ORG" && mkdir .be && {
    printf 'A\n' > a.txt
    "$BE" post '#c1' >/dev/null 2>&1
} )
# DIS-076: a bare post never mints a ref — pin the clone at ORG's own cur tip.
_orgtip() { ( cd "$1" && "$JABC" refs 2>/dev/null ) | sed -n 's/^cur: *//p'; }
ORG_TIP=$(_orgtip "$ORG")

# A tracked file with a full conflict triple → conflict-marker refusal, no write.
# TEST-003: jab-seeded store is unnamed-project, so clone bare `file://<store>`
# (no `?/org` selector — jab never mints a named `org` shard).
mkdir "$WORK/c"; ( cd "$WORK/c" && "$BE" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 )
{ printf '<<<<\ntheirs\n||||\nours\n>>>>\n'; } > "$WORK/c/a.txt"
( cd "$WORK/c" && "$BE" put a.txt >/dev/null 2>&1 )
C_TIP0=$(_tip "$WORK/c")
if ( cd "$WORK/c" && "$JABC" post '#merge' ) >"$WORK/c.out" 2>"$WORK/c.err"; then
    _fail "conflict post did NOT refuse (expected a conflict-marker refusal): $(cat "$WORK/c.out")"
fi
grep -q "conflict marker in tracked file a.txt" "$WORK/c.err" \
    || _fail "conflict post refused but not naming the marker'd file: $(cat "$WORK/c.err")"
[ "$(_tip "$WORK/c")" = "$C_TIP0" ] || _fail "conflict post mutated the store tip"

# --force overrides → the post lands.
( cd "$WORK/c" && "$JABC" post '#merge' --force ) >"$WORK/cf.out" 2>"$WORK/cf.err" \
    || _fail "--force post failed: $(cat "$WORK/cf.err")"
[ "$(_tip "$WORK/c")" != "$C_TIP0" ] || _fail "--force post did not advance the tip"

# A bare `<<<<` in prose (no partners) is NOT a conflict → posts fine.
mkdir "$WORK/p"; ( cd "$WORK/p" && "$BE" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 )
printf 'a diff shows <<<< as an open marker in docs\n' > "$WORK/p/a.txt"
( cd "$WORK/p" && "$BE" put a.txt >/dev/null 2>&1 )
( cd "$WORK/p" && "$JABC" post '#prose' ) >"$WORK/p.out" 2>"$WORK/p.err" \
    || _fail "prose post wrongly refused: $(cat "$WORK/p.err")"

pass
