#!/bin/sh
# test/js/post/conflict — POST-035/DIS-080: post's conflict gate is ROW-based,
# not byte-based.  A tracked path in the LIVE conflict set (`con` rows since the
# last get/post barrier — wtlog.conflicts(), ULOG-004) refuses in plain words,
# "conflict in tracked file <path> (--force overrides)", BEFORE any store write;
# DIS-080 §4: an explicit `put`/`delete` row LATER than the con row acks it, and
# `--force` believes everything resolved.  Posting IS the resolution: the new
# post row is the barrier, so conflicts() reads empty after (no row is deleted).
# Conflict-marker BYTES with no `con` row are just content now — they post fine.
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

# ULOG-004: the live conflict set of a worktree, space-joined (empty = none).
_conflicts() {
    cat > "$WORK/.con.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
const u=utf8.Encode(wtlog.open(info).conflicts().join(" ")+"\n");
const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.con.js" "$1" "$BEDIR" 2>/dev/null
}

# TEST-003: the rolling `.keeper.idx` indexes only the latest keeper, so drop it
# before each origin op or the t0 fork point both branches need reads MISSING.
_jab() { rm -f .be/*/*.keeper.idx 2>/dev/null; "$BE" "$@"; }
_orgbranch() { ( cd "$1" && "$JABC" refs 2>/dev/null ) | sed -n 's/^branch: *?//p'; }
_ci() {   # _ci MSG FILE... — stage + commit, then republish the branch ref.
    _msg=$1; shift
    _jab put "$@" >/dev/null 2>&1
    _jab post "$_msg" >/dev/null 2>&1
    _br=$(_orgbranch .); _jab post "?$_br" >/dev/null 2>&1
}

#  A trunk/feature divergence that TRULY conflicts on f.txt line 2:
#       t0 ── t1        ← trunk: line 2 = Y      (the branch we patch INTO)
#         \
#          f1           ← ?feat: line 2 = X
ORG="$WORK/org"; mkdir -p "$ORG/.be"
_opwd=$(pwd); cd "$ORG"
printf 'a\nb\nc\n' > f.txt
printf 'plain\n' > g.txt
_jab post 't0' >/dev/null 2>&1
BOOT=$(_orgtip .)
_jab put '?feat' >/dev/null 2>&1
_jab get '?feat' >/dev/null 2>&1
printf 'a\nX\nc\n' > f.txt
_ci 'f1 line2=X' f.txt
F1=$(_orgtip .)
_jab get "?#$BOOT" >/dev/null 2>&1          # back to trunk
printf 'a\nY\nc\n' > f.txt
_ci 't1 line2=Y' f.txt
cd "$_opwd"
ORG_TIP=$(_orgtip "$ORG")
rm -f "$ORG"/.be/*/*.keeper.idx 2>/dev/null

# --- 1. a live `con` row refuses the post, before any store write -----------
mkdir "$WORK/c"; ( cd "$WORK/c" && "$BE" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 ) \
    || _fail "clone failed"
# PATCH.mkd 2026-07-17: a conflicting patch exits NON-ZERO — that is expected.
( cd "$WORK/c" && "$JABC" patch "#$F1" ) >"$WORK/patch.out" 2>"$WORK/patch.err" || true
case " $(_conflicts "$WORK/c") " in
    *" f.txt "*) ;;
    *) _fail "patch left no live con row for f.txt: [$(_conflicts "$WORK/c")]" ;;
esac

C_TIP0=$(_tip "$WORK/c")
if ( cd "$WORK/c" && "$JABC" post '#merge' ) >"$WORK/c.out" 2>"$WORK/c.err"; then
    _fail "conflict post did NOT refuse (expected a row-based refusal): $(cat "$WORK/c.out")"
fi
grep -q "conflict in tracked file f.txt" "$WORK/c.err" \
    || _fail "conflict post refused but not naming the conflicted file: $(cat "$WORK/c.err")"
[ "$(_tip "$WORK/c")" = "$C_TIP0" ] || _fail "conflict post mutated the wt tip"

# --- 2. DIS-080 §4: an explicit `put` LATER than the con row is the ack ------
mkdir "$WORK/r"; ( cd "$WORK/r" && "$BE" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 ) \
    || _fail "clone failed (put-ack)"
( cd "$WORK/r" && "$JABC" patch "#$F1" ) >/dev/null 2>&1 || true
( cd "$WORK/r" && "$JABC" put f.txt ) >/dev/null 2>&1 || _fail "put of the conflicted file failed"
[ -z "$(_conflicts "$WORK/r")" ] \
    || _fail "the put did not ack the con row: [$(_conflicts "$WORK/r")]"
( cd "$WORK/r" && "$JABC" post '#resolved' ) >"$WORK/r.out" 2>"$WORK/r.err" \
    || _fail "post after an acking put wrongly refused: $(cat "$WORK/r.err")"

# --- 3. --force overrides → the post lands (commits the wt bytes) -----------
( cd "$WORK/c" && "$JABC" post '#merge' --force ) >"$WORK/cf.out" 2>"$WORK/cf.err" \
    || _fail "--force post failed: $(cat "$WORK/cf.err")"
[ "$(_tip "$WORK/c")" != "$C_TIP0" ] || _fail "--force post did not advance the tip"

# --- 4. posting IS the resolution: the post row is the barrier --------------
[ -z "$(_conflicts "$WORK/c")" ] \
    || _fail "post did not expire the con rows: [$(_conflicts "$WORK/c")]"

# --- 5. marker BYTES alone are content now (the byte pre-scan is gone) ------
mkdir "$WORK/p"; ( cd "$WORK/p" && "$BE" get "file://$ORG/.be#$ORG_TIP" >/dev/null 2>&1 )
{ printf '<<<<\ntheirs\n||||\nours\n>>>>\n'; } > "$WORK/p/g.txt"
( cd "$WORK/p" && "$BE" put g.txt >/dev/null 2>&1 )
( cd "$WORK/p" && "$JABC" post '#markers' ) >"$WORK/p.out" 2>"$WORK/p.err" \
    || _fail "marker-bytes post wrongly refused: $(cat "$WORK/p.err")"

pass
