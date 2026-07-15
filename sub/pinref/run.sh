#!/bin/sh
# test/sub/pinref — DIS-061: a sub's pin REF is maintained by the PARENT, never
# by the child's own commit (RULED 2026-07-13).
#   1. a sub's OWN commit advances the sub wt only: the sub goes "adv" (cur tip
#      descends the parent gitlink) and its synthetic-branch pin REF stays put.
#   2. the PARENT commit bumps the gitlink AND refreshes the child's pin REF to
#      that new gitlink (the pin tip IS the gitlink in the parent's new base).
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
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export BE JABC BEDIR

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# _subtip WT — the sub wt's current cur tip (40-hex) via wtlog.curTip().
cat > "$WORK/.subtip.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.find(process.argv[2]);
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
const info=be.find(process.argv[2]);
const k=store.open(info.storePath,info.project);
const cur=wtlog.open(info).curTip();const tip=cur&&cur.sha;let pin="";
if(tip){const tree=k.commitTree(tip);
  k.readTreeRecursive(tree,function(l){if(l.kind==="s"&&l.path===process.argv[4])pin=l.sha;});}
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w(pin);
EOF
_pin() { "$JABC" "$WORK/.pin.js" "$1" "$BEDIR" "$2" 2>/dev/null; }

# _pinref SUBWT — the sub's synthetic-branch pin REF (store.resolveRef of the
# sub's tracked branch KEY), "" when absent.  This is the row the PARENT owns.
cat > "$WORK/.pinref.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const store=require(process.argv[3]+"/shared/store.js");
const branchlib=require(process.argv[3]+"/shared/branch.js");
const info=be.find(process.argv[2]);
const att=wtlog.open(info).attachedBranch();
const k=store.open(info.storePath,info.project);
const key=branchlib.key(att.br);
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w((k.resolveRef(key)||"")+"\t"+key);
EOF
_pinref() { "$JABC" "$WORK/.pinref.js" "$1" "$BEDIR" 2>/dev/null | cut -f1; }

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
( cd "$WORK/P/sub" && "$BE" get "file://$WORK/storeS/.be" ) >"$WORK/gets.out" 2>&1 \
    || { cat "$WORK/gets.out"; _fail "mount sub"; }
[ -f "$WORK/P/sub/.be" ] || _fail "P/sub/.be not a FILE redirect (sub not mounted)"
S0=$(_subtip "$WORK/P/sub"); _is40 "$S0" "sub tip0"
_pinrow "sub" "$WORK/P/.be/wtlog" "$S0"
( cd "$WORK/P" && "$BE" post 'mount sub' ) >"$WORK/postp.out" 2>&1 || { cat "$WORK/postp.out"; _fail "commit sub gitlink"; }
[ "$(_pin "$WORK/P" sub)" = "$S0" ] || _fail "build: P.sub gitlink != sub tip"

# --- 1. the sub's OWN commit: sub goes adv, its pin REF stays put ------------
PINREF0=$(_pinref "$WORK/P/sub")            # "" — the parent has not set it yet
printf 'sub v2 EDITED\n' > "$WORK/P/sub/S.c"
( cd "$WORK/P/sub" && "$BE" put S.c >/dev/null 2>&1 && "$JABC" post '#s2' ) \
    >"$WORK/s2.out" 2>"$WORK/s2.err" || _fail "sub own commit failed: $(cat "$WORK/s2.err")"
S1=$(_subtip "$WORK/P/sub"); _is40 "$S1" "sub tip1"
[ "$S1" != "$S0" ] || _fail "sub commit did NOT advance the sub worktree"
# the gitlink in the parent is still S0 → the sub is "adv".
[ "$(_pin "$WORK/P" sub)" = "$S0" ] || _fail "sub own commit spuriously bumped the parent gitlink"
# RULED: the sub's own commit must NOT move its pin REF (parent owns it).
[ "$(_pinref "$WORK/P/sub")" = "$PINREF0" ] \
    || _fail "sub own commit MOVED its pin ref (child must not; parent owns the pin ref)"

# --- 2. the PARENT commit bumps the gitlink AND refreshes the pin REF --------
( cd "$WORK/P" && "$JABC" post '#absorb sub' ) >"$WORK/pp.out" 2>"$WORK/pp.err" \
    || _fail "parent absorb post failed: $(cat "$WORK/pp.err")"
[ "$(_pin "$WORK/P" sub)" = "$S1" ] || _fail "parent commit did NOT bump the sub gitlink to S1"
[ "$(_pinref "$WORK/P/sub")" = "$S1" ] \
    || _fail "parent commit did NOT refresh the sub pin ref to the new gitlink ($S1; got $(_pinref "$WORK/P/sub"))"

echo "PASS [$NAME]"
