#!/bin/sh
# test/js/post/conflict — `bin/post.js` POST-017 conflict pre-scan: a tracked
# `add` carrying a complete WEAVE conflict-marker triple must refuse POSTCFLCT
# BEFORE any store write, and `--force` overrides it.  A bare `<<<<` in prose
# (no `||||`/`>>>>` partners) is NOT a conflict and posts fine.
. "$(dirname "$0")/../../lib/postcase.sh"

_tip() {
    cat > "$WORK/.tip.js" <<'EOF'
const be=require(process.argv[3]+"/lib/be.js");
const store=require(process.argv[3]+"/lib/store.js");
const info=be.find(process.argv[2]);
const k=store.open(info.storePath,info.project);
const u=utf8.Encode((k.resolveRef("")||"")+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.tip.js" "$1" "$BEDIR" 2>/dev/null
}

ORG="$WORK/org"; mkdir -p "$ORG"; ( cd "$ORG" && mkdir .be && {
    printf 'A\n' > a.txt
    "$BE" post '#c1' >/dev/null 2>&1
} )

# A tracked file with a full conflict triple → POSTCFLCT, no write.
mkdir "$WORK/c"; ( cd "$WORK/c" && "$BE" get "file://$ORG/.be?/org" >/dev/null 2>&1 )
{ printf '<<<<\ntheirs\n||||\nours\n>>>>\n'; } > "$WORK/c/a.txt"
( cd "$WORK/c" && "$BE" put a.txt >/dev/null 2>&1 )
C_TIP0=$(_tip "$WORK/c")
if ( cd "$WORK/c" && "$JABC" "$POSTJS" '#merge' ) >"$WORK/c.out" 2>"$WORK/c.err"; then
    _fail "conflict post did NOT refuse (expected POSTCFLCT): $(cat "$WORK/c.out")"
fi
grep -q POSTCFLCT "$WORK/c.err" || _fail "conflict post refused but not POSTCFLCT: $(cat "$WORK/c.err")"
[ "$(_tip "$WORK/c")" = "$C_TIP0" ] || _fail "conflict post mutated the store tip"

# --force overrides → the post lands.
( cd "$WORK/c" && "$JABC" "$POSTJS" '#merge' --force ) >"$WORK/cf.out" 2>"$WORK/cf.err" \
    || _fail "--force post failed: $(cat "$WORK/cf.err")"
[ "$(_tip "$WORK/c")" != "$C_TIP0" ] || _fail "--force post did not advance the tip"

# A bare `<<<<` in prose (no partners) is NOT a conflict → posts fine.
mkdir "$WORK/p"; ( cd "$WORK/p" && "$BE" get "file://$ORG/.be?/org" >/dev/null 2>&1 )
printf 'a diff shows <<<< as an open marker in docs\n' > "$WORK/p/a.txt"
( cd "$WORK/p" && "$BE" put a.txt >/dev/null 2>&1 )
( cd "$WORK/p" && "$JABC" "$POSTJS" '#prose' ) >"$WORK/p.out" 2>"$WORK/p.err" \
    || _fail "prose post wrongly refused: $(cat "$WORK/p.err")"

pass
