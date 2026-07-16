#!/bin/sh
# test/sub/pinref — DIS-072: a mounted sub's pin is a `get //WT/path/sub#<gitlink>`
# row in the SUB's own wtlog, rewritten ONLY by the PARENT's post (POST-027 postSubs).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/sub/pinref
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "pinref: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "pinref: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/sub/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export BE JABC BEDIR

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# _subtip WT — the sub wt's current cur tip (40-hex) via wtlog.curTip().
cat > "$WORK/.subtip.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
const cur=wtlog.open(info).curTip();
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w((cur&&cur.sha)||"");
EOF
_subtip() { "$JABC" "$WORK/.subtip.js" "$1" "$BEDIR" 2>/dev/null; }

# _pin WT SUBPATH — the 40-hex gitlink pin for SUBPATH in WT's BASE tree (the wt
# cur tip, which is what subs.js classifies against — NOT the branch ref, which
# under the uniform model lags the wt).
cat > "$WORK/.pin.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
const k=store.open(info.storePath,info.project);
const cur=wtlog.open(info).curTip();const tip=cur&&cur.sha;let pin="";
if(tip){const tree=k.commitTree(tip);
  k.readTreeRecursive(tree,function(l){if(l.kind==="s"&&l.path===process.argv[4])pin=l.sha;});}
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w(pin);
EOF
_pin() { "$JABC" "$WORK/.pin.js" "$1" "$BEDIR" "$2" 2>/dev/null; }

# _lastget SUBWT — the recentmost `get` row in SUBWT's OWN wtlog, printed as
# `A=<authority> P=<path> F=<fragment>` (shared/wtlog.js rows, the
# test/post/wt-target-detached probe pattern).  This is the pin row the
# PARENT owns (DIS-072 re-attach).
cat > "$WORK/.lastget.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
let last;
for(const r of wtlog.open(info).rows) if(r.verb==="get") last=r;
let s;
if(!last) s="NOROW";
else s="A="+(last.uri.authority==null?"":last.uri.authority)
       +" P="+(last.uri.path||"")+" F="+(last.uri.fragment||"");
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w(s);
EOF
_lastget() { "$JABC" "$WORK/.lastget.js" "$1" "$BEDIR" 2>/dev/null; }

# _pinrow SUBPATH WTLOG SHA — seed a `put <subpath>#<sha>` gitlink-bump row.
cat > "$WORK/.pinrow.js" <<'EOF'
const ulog=require(process.argv[2]+"/shared/ulog.js");
ulog.append(process.argv[4],[{verb:"put",uri:URI.make(undefined,undefined,process.argv[3],undefined,process.argv[5])}]);
EOF
_pinrow() { "$JABC" "$WORK/.pinrow.js" "$BEDIR" "$1" "$2" "$3" >/dev/null 2>&1 || true; }

_is40() { case "$1" in ????????????????????????????????????????) ;; *) _fail "$2: not 40-hex: '$1'";; esac; }

# --- build a 2-level tree: parent P with sub S mounted + gitlinked (clean) ----
mkdir -p "$WORK/storeS/.be" "$WORK/P/.be"
( cd "$WORK/storeS" && printf 'sub v1\n' > S.c && "$BE" post 'sub initial' ) >/dev/null 2>&1 || _fail "storeS setup"
( cd "$WORK/P"      && printf 'top v1\n' > TOP.c && "$BE" post 'parent initial' ) >/dev/null 2>&1 || _fail "P setup"
mkdir -p "$WORK/P/sub"
# DIS-076: a bare post never mints a ref — pin the mount clone at storeS's own tip.
_stip=$(_subtip "$WORK/storeS")
( cd "$WORK/P/sub" && "$BE" get "file://$WORK/storeS/.be#$_stip" ) >"$WORK/gets.out" 2>&1 \
    || { cat "$WORK/gets.out"; _fail "mount sub"; }
[ -f "$WORK/P/sub/.be" ] || _fail "P/sub/.be not a FILE redirect (sub not mounted)"
S0=$(_subtip "$WORK/P/sub"); _is40 "$S0" "sub tip0"
_pinrow "sub" "$WORK/P/.be/wtlog" "$S0"
( cd "$WORK/P" && "$BE" post 'mount sub' ) >"$WORK/postp.out" 2>&1 || { cat "$WORK/postp.out"; _fail "commit sub gitlink"; }
[ "$(_pin "$WORK/P" sub)" = "$S0" ] || _fail "build: P.sub gitlink != sub tip"

# --- 1. the sub's OWN commit: sub goes adv, its pin row stays put ------------
GET0=$(_lastget "$WORK/P/sub")              # the mount-time get row
printf 'sub v2 EDITED\n' > "$WORK/P/sub/S.c"
( cd "$WORK/P/sub" && "$BE" put S.c >/dev/null 2>&1 && "$JABC" post '#s2' ) \
    >"$WORK/s2.out" 2>"$WORK/s2.err" || _fail "sub own commit failed: $(cat "$WORK/s2.err")"
S1=$(_subtip "$WORK/P/sub"); _is40 "$S1" "sub tip1"
[ "$S1" != "$S0" ] || _fail "sub commit did NOT advance the sub worktree"
# the gitlink in the parent is still S0 → the sub is "adv".
[ "$(_pin "$WORK/P" sub)" = "$S0" ] || _fail "sub own commit spuriously bumped the parent gitlink"
# RULED (DIS-072): the sub's own commit must NOT write a pin row (parent owns it).
[ "$(_lastget "$WORK/P/sub")" = "$GET0" ] \
    || _fail "sub own commit MOVED its pin row (child must not; parent owns the pin row)"

# --- 2. the PARENT commit bumps the gitlink AND rewrites the pin row ---------
( cd "$WORK/P" && "$JABC" post '#absorb sub' ) >"$WORK/pp.out" 2>"$WORK/pp.err" \
    || _fail "parent absorb post failed: $(cat "$WORK/pp.err")"
[ "$(_pin "$WORK/P" sub)" = "$S1" ] || _fail "parent commit did NOT bump the sub gitlink to S1"
# DIS-072 re-attach: the CHILD's wtlog recentmost get row is the parent-written
# pin URI `//<parentwt>/sub#<newgitlink>` (P is a standalone tree → `///sub`).
ROW=$(_lastget "$WORK/P/sub")
[ "$ROW" = "A=// P=/sub F=$S1" ] \
    || _fail "parent commit did NOT re-attach the sub pin row (want A=// P=/sub F=$S1; got $ROW)"

echo "PASS [$NAME]"
