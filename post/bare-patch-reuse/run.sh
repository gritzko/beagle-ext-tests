#!/bin/sh
# test/post/bare-patch-reuse — POST-027 cell 1c EXCEPTION: with an ACTIVE
# absorbed patch, a message-less post REUSES the absorbed commit message.
# POST.mkd §"Summary of invocation patterns" cell 1: "exception: an active
# patch reuses the absorbed message"; §CLI: "`#` — reuse absorbed msg (empty
# fragment)" and "(empty) bare: reuse absorbed msg (patch)".  So on a wt
# carrying a patch-merged (`mrg`) tree, BOTH a bare `jab post` and a
# `jab post '#'` must COMMIT the absorbed content, and the new commit's
# message must equal the patched-in (theirs) commit's own message.  The
# patch fixture is post/patch-absorb's disjoint-line 3-way merge; the
# commit-body probe decodes the message like sub/selfloop decodes a blob.
# RED today: NO absorbed-message reuse path exists — parseMessage never
# consults the patch row, and post.js:780 routes every message-less post
# into the DIS-074 ADVANCE arm: a bare `post` mints/advances the track ref
# and makes NO commit (cur stays put, the patch is left unconsumed), and
# `post '#'` refuses POSTNONE "already at".
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/bare-patch-reuse
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/bare-patch-reuse: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/bare-patch-reuse: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
# Pin the clock so the builder shas are stable (the post/patch-absorb pin).
: "${SOURCE_DATE_EPOCH:=1467331200}"; export SOURCE_DATE_EPOCH   # 2016-07-01Z
: "${TZ:=UTC}"; export TZ

: "${TMP:=/tmp}"; export TMP
NAME=bare-patch-reuse
WORK="$TMP/$$/post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [post/$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [post/$NAME]"; }

. "$_ROOT/lib/repo-setup.sh"

# URI-016: SRC is the PROJECT ROOT (its own `.be/` anchor); clone wts under
# `work/` share the PROJECT store (the test/post/bare-advance shape-2
# layout); BE_ROOT confines the climb above SRC.
SRC="$WORK/src"
WORKD=$(rs_work_root "$SRC")
ln -sfn "$BEDIR" "$SRC/jsrc"
export BE_ROOT="$WORK"

# tip capture: the worktree's own cur via `jab refs` — never od/grep `.be/refs`.
_cur() { ( cd "$1" && "$JABC" refs ) 2>/dev/null | sed -n 's/^cur: *//p'; }
# in-scope status rows (the post/patch-absorb probe).
_jstatus() { ( cd "$1" && "$JABC" status --plain 2>/dev/null ) \
    | sed -nE 's/^.{8}([.xovXOV!]{4}) (.*)$/\1 \2/p'; }
# the MESSAGE of commit $3 as seen from wt $1 (sub/selfloop's commit-body
# decode: store.open + getObject, the message is past the header's blank line).
_msg() {   # _msg DIR SHA
    cat > "$WORK/.msg.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const store=require(process.argv[3]+"/shared/store.js");
const info=be.treeAt(process.argv[2]);
const k=store.open(info.storePath,info.project);
const o=k.getObject(process.argv[4]);
let msg="";
if(o&&o.bytes){const t=utf8.Decode(o.bytes);const i=t.indexOf("\n\n");if(i>=0)msg=t.slice(i+2);}
const u=utf8.Encode(msg);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.msg.js" "$1" "$BEDIR" "$2" 2>/dev/null
}
# The rolling keeper.idx indexes only the LATEST keeper (the test/post/
# patch-absorb note); drop the stale idx in BOTH stores before old-object reads.
_fresh() { rm -f "$ORG"/.be/*.keeper.idx "$ORG"/.be/*/*.keeper.idx \
                 "$SRC"/.be/*.keeper.idx "$SRC"/.be/*/*.keeper.idx 2>/dev/null || true; }

# ===== fixture: the patch-absorb disjoint-line merge org =====================
# org: trunk t0 (a..e), feat f1 edits line 4 (msg `f1` — THE absorbed message),
# trunk t1 edits line 2 — a clean 3-way merge when f1 is patched onto t1.
ORG="$WORKD/org"; mkdir -p "$ORG/.be"
( cd "$ORG"
  printf 'a\nb\nc\nd\ne\n' > f.txt
  "$BE" post '#t0' ) >/dev/null 2>&1 || _fail "org: bootstrap post t0 failed"
T0=$(_cur "$ORG"); [ -n "$T0" ] || _fail "org: no t0 tip"
( cd "$ORG" && "$JABC" post '?feat' && "$JABC" get '?feat' ) >/dev/null 2>&1 \
    || _fail "org: publish+attach ?feat failed"
( cd "$ORG"
  printf 'a\nb\nc\nD\ne\n' > f.txt
  "$JABC" put f.txt && "$JABC" post '#f1' ) >/dev/null 2>&1 || _fail "org: post f1 failed"
F1=$(_cur "$ORG"); [ -n "$F1" ] || _fail "org: no f1 tip"
_fresh
( cd "$ORG" && "$JABC" get "?#$T0" ) >/dev/null 2>&1 || _fail "org: back to trunk@t0 failed"
( cd "$ORG"
  printf 'a\nB\nc\nd\ne\n' > f.txt
  "$JABC" put f.txt && "$JABC" post '#t1' ) >/dev/null 2>&1 || _fail "org: post t1 failed"
T1=$(_cur "$ORG"); [ -n "$T1" ] && [ "$T1" != "$F1" ] || _fail "org: no distinct t1 tip"
_fresh
F1MSG=$(_msg "$ORG" "$F1")
[ "$F1MSG" = "f1" ] || _fail "fixture: theirs message probe broken (got [$F1MSG])"

# _absorbwt DIR — clone org@t1 into DIR and patch f1 in (an ACTIVE absorbed
# patch, `mrg f.txt` in scope).
_absorbwt() {
    mkdir -p "$1"
    _fresh
    ( cd "$1" && "$JABC" get "file://$ORG/.be#$T1" ) >/dev/null 2>&1 \
        || _fail "$(basename "$1"): clone of org@t1 failed"
    _fresh
    ( cd "$1" && "$JABC" patch "#$F1" ) >/dev/null 2>&1 \
        || _fail "$(basename "$1"): patch #f1 failed"
    # BRO-030 quad default: an absorbed patch-merged file reads `..vv`.
    st=$(_jstatus "$1")
    [ "$st" = "..vv f.txt" ] \
        || _fail "$(basename "$1"): absorbed-patch status != '..vv f.txt': $st"
}

# ===== leg 1: a BARE post reuses the absorbed message ========================
CA="$WORKD/CA"; _absorbwt "$CA"
_fresh
RC=0
( cd "$CA" && "$JABC" post ) >"$WORK/a.out" 2>"$WORK/a.err" || RC=$?
NEWA=$(_cur "$CA")
if [ "$RC" -ne 0 ] || [ -z "$NEWA" ] || [ "$NEWA" = "$T1" ]; then
    echo "post/bare-patch-reuse: RED (rc=$RC) — a bare post with an active absorbed patch made NO reuse commit (POST.mkd cell 1: the patch exception)" >&2
    echo "  stdout: $(cat "$WORK/a.out")" >&2
    echo "  stderr: $(cat "$WORK/a.err")" >&2
    echo "  cur before=$T1 after=$NEWA (must be a NEW commit)" >&2
    _fail "bare post did not commit the absorbed patch (see above)"
fi
_fresh
AMSG=$(_msg "$CA" "$NEWA")
[ "$AMSG" = "$F1MSG" ] \
    || _fail "bare post's commit message [$AMSG] != the absorbed message [$F1MSG]"

# ===== leg 2: `post '#'` (empty fragment) reuses the absorbed message ========
CB="$WORKD/CB"; _absorbwt "$CB"
_fresh
RC=0
( cd "$CB" && "$JABC" post '#' ) >"$WORK/b.out" 2>"$WORK/b.err" || RC=$?
NEWB=$(_cur "$CB")
if [ "$RC" -ne 0 ] || [ -z "$NEWB" ] || [ "$NEWB" = "$T1" ]; then
    echo "post/bare-patch-reuse: RED (rc=$RC) — post '#' with an active absorbed patch made NO reuse commit (POST.mkd CLI: '#' reuses the absorbed msg)" >&2
    echo "  stdout: $(cat "$WORK/b.out")" >&2
    echo "  stderr: $(cat "$WORK/b.err")" >&2
    echo "  cur before=$T1 after=$NEWB (must be a NEW commit)" >&2
    _fail "post '#' did not commit the absorbed patch (see above)"
fi
_fresh
BMSG=$(_msg "$CB" "$NEWB")
[ "$BMSG" = "$F1MSG" ] \
    || _fail "post '#'s commit message [$BMSG] != the absorbed message [$F1MSG]"

pass
