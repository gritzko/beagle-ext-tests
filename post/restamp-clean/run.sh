#!/bin/sh
# test/post/restamp-clean — POST-037: a post CONTENT-HASHES every tracked file
# whose mtime is off the wtlog stamp-set (classify's `wtEqBase` leg) and, when
# the file proves CLEAN, must not throw that verdict away: the BE-011 restamp
# loop stamps those content-confirmed-ok paths to the SAME assigned post row ts
# it stamps the posted files with, so the NEXT status confirms them clean with
# ZERO content reads (STATUS-011 fast path).  Sibling of test/post/restamp,
# which covers the files a post UNDIRTIES ([/todo/POST/POST-029]); this case
# covers the files a post merely CONFIRMS.  Three classes, each: set a
# randomized off-stamp-set mtime on clean tracked files, post, then assert (via
# .stampchk.js, the SAME wtlog.open/classify readers status.js uses) that those
# mtimes are in wtlogReader.has() AND classify opens none of them:
#   E. commit-all post (bare `mod` sibling drives the commit);
#   F. selective post (`put` one file, the clean ones ride along);
#   G. a sub post folding a gitlink bump — the SUB's own clean interior file
#      (get-materialised, so never stamped: GET-049) + the parent's clean file.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/restamp-clean
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${JAB:-${BIN:+$BIN/jab}}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/restamp-clean: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "post/restamp-clean: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the jsrc shard symlink (jab's upward jsrc-scan resolves
# the JS verbs from the worktree under test, above the /tmp fixtures).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# --- randomized off-stamp-set mtimes -----------------------------------------
# `_scuff FILE...` back-dates each file to a pid-derived, per-call-varying epoch
# second in 2023 — far below any wtlog row ts, so its mtime is NOT in the
# stamp-set and classify MUST content-hash the file to call it clean.  Content
# is untouched: every scuffed file stays byte-identical to its baseline blob.
_SCUFF_N=0
_scuff() {
    for f in "$@"; do
        _SCUFF_N=$((_SCUFF_N + 1))
        _t=$((1670000000 + ($$ * 7919 + _SCUFF_N * 104729) % 30000000))
        touch -d "@$_t" "$f" || _fail "touch -d failed on $f"
    done
}

# --- the POST-037 invariant checker ------------------------------------------
# jab .stampchk.js BEDIR WT rel...  — for each rel: mtime ∈ wtl.has() (the
# STATUS-011 reader, post-post); then ONE classify.classify run (the status.js
# call shape) with io.open hooked: none of the rels content-read, no dirty rows.
cat > "$WORK/.stampchk.js" <<'EOF'
const bedir = process.argv[2], wt = process.argv[3];
const rels  = process.argv.slice(4);
const discover = require(bedir + "/core/discover.js");
const wtlog    = require(bedir + "/shared/wtlog.js");
const store    = require(bedir + "/shared/store.js");
const classify = require(bedir + "/shared/classify.js");
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
const info = discover.treeAt(wt);
const wtl  = wtlog.open(info);           // THE reader status uses (status.js:278)
const k    = store.open(info.storePath, info.project);
const bad = [];
for (const rel of rels) {
  let m;
  try { m = io.lstat(info.wt + "/" + rel).mtime; }
  catch (e) { bad.push("NOFILE " + rel); continue; }
  if (!wtl.has(m)) bad.push("NOSTAMP " + rel + " mtime=" + ron.encode(m));
}
const opened = [], realOpen = io.open;
io.open = function (p) { opened.push(String(p)); return realOpen.apply(io, arguments); };
let res;
try { res = classify.classify(info, wtl, k); } finally { io.open = realOpen; }
for (const rel of rels) {
  const full = info.wt + "/" + rel;
  for (const p of opened) if (p === full) { bad.push("READ " + rel); break; }
}
for (const r of res.rows) bad.push("DIRTY " + r.bucket + " " + r.path);
if (bad.length) { w("stampchk FAIL " + wt + "\n" + bad.join("\n") + "\n");
                  throw "stampchk: " + bad.length + " violation(s)"; }
w("stampchk ok " + wt + " (" + rels.length + " files)\n");
EOF
_chk() { _w=$1; shift; "$JABC" "$WORK/.stampchk.js" "$BEDIR" "$_w" "$@" \
    || _fail "invariant broken in $_w ($*)"; }

# _subtip WT — a wt's cur tip (40-hex), via the wtlog reader (subcase probe).
cat > "$WORK/.subtip.js" <<'EOF'
const be    = require(process.argv[3] + "/core/discover.js");
const wtlog = require(process.argv[3] + "/shared/wtlog.js");
const cur = wtlog.open(be.treeAt(process.argv[2])).curTip();
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w((cur && cur.sha) || "");
EOF
_subtip() { "$JABC" "$WORK/.subtip.js" "$1" "$BEDIR" 2>/dev/null; }

# _pinrow SUBPATH WTLOG SHA — seed a `put <subpath>#<sha>` gitlink-bump row
# (jab has no CLI spelling for a manual gitlink pin; subcase.sh's recipe).
cat > "$WORK/.pinrow.js" <<'EOF'
const ulog = require(process.argv[2] + "/shared/ulog.js");
ulog.append(process.argv[4], [{ verb: "put",
  uri: URI.make(undefined, undefined, process.argv[3], undefined, process.argv[5]) }]);
EOF
_pinrow() { "$JABC" "$WORK/.pinrow.js" "$BEDIR" "$1" "$2" "$3" >/dev/null 2>&1 || true; }

# ============================================================================
# E. commit-all post: one bare `mod` file drives the commit; b/c are CLEAN but
#    scuffed off the stamp-set, so classify hashes them — and the post must
#    stamp that confirmed-clean verdict.
# ============================================================================
WE="$WORK/e"; mkdir -p "$WE/.be"
( cd "$WE" && printf 'A1\n' > a.txt && printf 'B1\n' > b.txt \
    && printf 'C1\n' > c.txt && "$BE" post '#base' ) >/dev/null 2>&1 || _fail "E: seed"
sleep 0.02
printf 'A2\n' > "$WE/a.txt"
_scuff "$WE/b.txt" "$WE/c.txt"
# Precheck: only a.txt is dirty (`...v`, a bare unstaged edit); the scuffed
# files are content-confirmed CLEAN, so they raise no row.
st=$( cd "$WE" && "$BE" status --plain 2>/dev/null | sed -nE 's/^.{8}([.xovXOV!]{4}) (.*)$/\1 \2/p' )
[ "$st" = "...v a.txt" ] || _fail "E: precheck != '...v a.txt': $st"
( cd "$WE" && "$BE" post '#commit all' ) >/dev/null 2>&1 || _fail "E: post"
_chk "$WE" a.txt b.txt c.txt
echo "ok   E. commit-all post: content-confirmed clean files stamped, 0 reads"

# ============================================================================
# F. selective post (`put a.txt`): the clean scuffed siblings are `keep`s, and
#    their confirmed verdict must be stamped just the same.
# ============================================================================
WF="$WORK/f"; mkdir -p "$WF/.be"
( cd "$WF" && printf 'A1\n' > a.txt && printf 'B1\n' > b.txt \
    && printf 'C1\n' > c.txt && "$BE" post '#base' ) >/dev/null 2>&1 || _fail "F: seed"
sleep 0.02
printf 'A2\n' > "$WF/a.txt"
( cd "$WF" && "$BE" put a.txt ) >/dev/null 2>&1 || _fail "F: put a.txt"
_scuff "$WF/b.txt" "$WF/c.txt"
st=$( cd "$WF" && "$BE" status --plain 2>/dev/null | sed -nE 's/^.{8}([.xovXOV!]{4}) (.*)$/\1 \2/p' )
[ "$st" = "...V a.txt" ] || _fail "F: precheck != '...V a.txt': $st"
( cd "$WF" && "$BE" post '#staged a' ) >/dev/null 2>&1 || _fail "F: post"
_chk "$WF" a.txt b.txt c.txt
echo "ok   F. selective post: clean siblings stamped, 0 reads"

# ============================================================================
# G. a sub post folding a gitlink bump: the sub's helper.c was materialised by
#    the mount `jab get` (which stamps nothing — GET-049), so it is clean and
#    OFF the stamp-set; the parent's main.c is scuffed the same way.  One
#    ctx.now drives the parent's and the sub's post rows.
# ============================================================================
SUB="$WORK/substore"; mkdir -p "$SUB/.be"
( cd "$SUB" && printf 'sub payload v1\n' > lib.c && printf 'sub helper\n' > helper.c \
    && "$BE" post '#sub initial' ) >/dev/null 2>&1 || _fail "G: sub seed"
PD="$WORK/par"; mkdir -p "$PD/.be"
( cd "$PD" && printf 'int main(void){return 0;}\n' > main.c \
    && "$BE" post '#parent initial' ) >/dev/null 2>&1 || _fail "G: parent seed"
STIP=$(_subtip "$SUB")
mkdir -p "$PD/vendor/sub"
( cd "$PD/vendor/sub" && "$BE" get "file://$SUB/.be#$STIP" ) >"$WORK/getsub.out" 2>&1 \
    || { cat "$WORK/getsub.out"; _fail "G: mount sub"; }
[ -f "$PD/vendor/sub/.be" ] || _fail "G: vendor/sub/.be not a FILE redirect"
cat > "$PD/.gitmodules" <<EOF
[submodule "vendor/sub"]
	path = vendor/sub
	url = file://$SUB/.be?/sub
EOF
( cd "$PD" && "$BE" put .gitmodules ) >/dev/null 2>&1 || _fail "G: put .gitmodules"
_pinrow "vendor/sub" "$PD/.be/wtlog" "$STIP"
( cd "$PD" && "$BE" post '#mount sub' ) >/dev/null 2>&1 || _fail "G: mount post"
sleep 0.02
printf 'sub payload v2 EDITED\n' > "$PD/vendor/sub/lib.c"
( cd "$PD/vendor/sub" && "$BE" put lib.c ) >/dev/null 2>&1 || _fail "G: put lib.c in sub"
_scuff "$PD/main.c" "$PD/vendor/sub/helper.c"
( cd "$PD" && "$BE" post '#bump sub' ) >"$WORK/postg.out" 2>"$WORK/postg.err" \
    || { cat "$WORK/postg.err"; _fail "G: top post"; }
STIP1=$(_subtip "$PD/vendor/sub")
[ "$STIP1" != "$STIP" ] || _fail "G: sub did not commit under the top post"
_chk "$PD/vendor/sub" lib.c helper.c
_chk "$PD" main.c .gitmodules
echo "ok   G. sub post: sub + parent clean files stamped, 0 reads"

echo "PASS [$NAME]"
