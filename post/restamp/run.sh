#!/bin/sh
# test/post/restamp — POST-029: every file a post UNDIRTIES carries a
# wtlog-stamp mtime afterwards (the BE-011 post.js restamp), so the next status
# confirms it clean with ZERO content reads (STATUS-011 fast path).  Four
# classes, each: post, then assert (via .stampchk.js, the SAME wtlog.open/
# classify readers status.js uses) that every undirtied file's mtime is in
# wtlogReader.has() AND classify opens none of them, all-ok buckets:
#   A. put-staged file post (put-row + post restamp; put row survives in wtlog);
#   B. commit-all post over bare `mod` files never put-stamped (PUT-009 ruling);
#   C. a staged move (`put src#dst`) post — the DESTINATION file;
#   D. a sub post folding a gitlink bump — sub interior + parent rows.
# The -aged mode additionally requires a checked mtime STRICTLY BELOW the pd
# boundary the post just moved: has() must be scope-blind (whole stamp-set), a
# stamp aging out of has() would be a fast-path hole even with a correct mtime.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/restamp
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${JAB:-${BIN:+$BIN/jab}}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/restamp: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "post/restamp: SKIP — no $BEDIR/main.js" >&2; exit 0; }
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

# `jab status` reduced to date-normalised `<bucket> <path>` rows (post/move's).
_jstatus() { ( cd "$1" && "$JABC" status --plain 2>/dev/null ) \
    | sed -nE 's/^ *[0-9A-Za-z:]+ +([a-z]{3}) +(.*)$/\1 \2/p'; }

# --- the POST-029 invariant checker ------------------------------------------
# jab .stampchk.js BEDIR MODE WT rel...  — for each rel: mtime ∈ wtl.has() (the
# STATUS-011 reader, post-post); then ONE classify.classify run (the status.js
# call shape) with io.open hooked: none of the rels content-read, no dirty rows.
cat > "$WORK/.stampchk.js" <<'EOF'
const bedir = process.argv[2], mode = process.argv[3], wt = process.argv[4];
const rels  = process.argv.slice(5);
const discover = require(bedir + "/core/discover.js");
const wtlog    = require(bedir + "/shared/wtlog.js");
const store    = require(bedir + "/shared/store.js");
const classify = require(bedir + "/shared/classify.js");
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
const info = discover.treeAt(wt);
const wtl  = wtlog.open(info);           // THE reader status uses (status.js:278)
const k    = store.open(info.storePath, info.project);
const pd   = wtl.boundaries().pd;
let aged = 0; const bad = [], mts = {};
for (const rel of rels) {
  let m;
  try { m = io.lstat(info.wt + "/" + rel).mtime; }
  catch (e) { bad.push("NOFILE " + rel); continue; }
  mts[rel] = m;
  if (!wtl.has(m)) bad.push("NOSTAMP " + rel + " mtime=" + ron.encode(m) +
                            " pd=" + (pd == null ? "-" : ron.encode(pd)));
  if (pd != null && m < pd) aged++;      // stamp OLDER than the moved pd boundary
}
if (mode === "-aged" && !aged)
  bad.push("AGEDNONE: no checked mtime below the pd boundary (vacuous case)");
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
w("stampchk ok " + wt + " (" + rels.length + " files, " + aged + " aged-past-pd)\n");
EOF
_chk() { _m=$1; _w=$2; shift 2; "$JABC" "$WORK/.stampchk.js" "$BEDIR" "$_m" "$_w" "$@" \
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
# A. put-staged file, then post — the put row survives in the wtlog and the
#    post restamp keeps the file's mtime in the stamp-set.
# ============================================================================
WA="$WORK/a"; mkdir -p "$WA/.be"
( cd "$WA" && printf 'A1\n' > a.txt && printf 'B1\n' > b.txt \
    && "$BE" post '#base' ) >/dev/null 2>&1 || _fail "A: seed"
sleep 0.02
printf 'A2\n' > "$WA/a.txt"
( cd "$WA" && "$BE" put a.txt ) >/dev/null 2>&1 || _fail "A: put a.txt"
st=$(_jstatus "$WA"); [ "$st" = "put a.txt" ] || _fail "A: precheck != 'put a.txt': $st"
( cd "$WA" && "$BE" post '#staged a' ) >/dev/null 2>&1 || _fail "A: post"
grep -qE "put[[:space:]]+a\.txt" "$WA/.be/wtlog" \
    || _fail "A: the consumed put row vanished from the wtlog"
_chk -aged "$WA" a.txt b.txt          # b.txt's stamp is below the moved pd
echo "ok   A. put-staged post: restamped, put row survives, 0 reads"

# ============================================================================
# B. commit-all post over bare `mod` files never put-stamped (the suspect gap).
# ============================================================================
WB="$WORK/b"; mkdir -p "$WB/.be"
( cd "$WB" && printf 'A1\n' > a.txt && printf 'B1\n' > b.txt \
    && printf 'C1\n' > c.txt && "$BE" post '#base' ) >/dev/null 2>&1 || _fail "B: seed"
sleep 0.02
printf 'A2\n' > "$WB/a.txt"; printf 'B2\n' > "$WB/b.txt"
st=$(_jstatus "$WB")
[ "$st" = "mod a.txt
mod b.txt" ] || _fail "B: precheck != two mod rows: $st"
( cd "$WB" && "$BE" post '#commit all' ) >/dev/null 2>&1 || _fail "B: post"
_chk -aged "$WB" a.txt b.txt c.txt    # c.txt untouched: its stamp is pre-pd
echo "ok   B. commit-all post: mod files restamped, 0 reads"

# ============================================================================
# C. a staged move, then post — the DESTINATION file is the undirtied one.
# ============================================================================
WC="$WORK/c"; mkdir -p "$WC/.be"
( cd "$WC" && printf 'A1\n' > a.txt && printf 'B1\n' > b.txt \
    && "$BE" post '#base' ) >/dev/null 2>&1 || _fail "C: seed"
sleep 0.02
( cd "$WC" && "$BE" put 'b.txt#m.txt' ) >/dev/null 2>&1 || _fail "C: put move"
( cd "$WC" && "$BE" post '#rename' ) >/dev/null 2>&1 || _fail "C: post"
[ -f "$WC/m.txt" ] || _fail "C: m.txt missing after the move post"
_chk -aged "$WC" a.txt m.txt
echo "ok   C. move post: destination restamped, 0 reads"

# ============================================================================
# D. a sub post folding a gitlink bump — sub interior files + parent rows.
#    The parent's post RE-ATTACHES the sub (a get row PAST the sub's post
#    stamp), so the sub files' stamps sit below the sub's own moved pd.
# ============================================================================
SUB="$WORK/substore"; mkdir -p "$SUB/.be"
( cd "$SUB" && printf 'sub payload v1\n' > lib.c && printf 'sub helper\n' > helper.c \
    && "$BE" post '#sub initial' ) >/dev/null 2>&1 || _fail "D: sub seed"
PD="$WORK/par"; mkdir -p "$PD/.be"
( cd "$PD" && printf 'int main(void){return 0;}\n' > main.c \
    && "$BE" post '#parent initial' ) >/dev/null 2>&1 || _fail "D: parent seed"
STIP=$(_subtip "$SUB")
mkdir -p "$PD/vendor/sub"
( cd "$PD/vendor/sub" && "$BE" get "file://$SUB/.be#$STIP" ) >"$WORK/getsub.out" 2>&1 \
    || { cat "$WORK/getsub.out"; _fail "D: mount sub"; }
[ -f "$PD/vendor/sub/.be" ] || _fail "D: vendor/sub/.be not a FILE redirect"
cat > "$PD/.gitmodules" <<EOF
[submodule "vendor/sub"]
	path = vendor/sub
	url = file://$SUB/.be?/sub
EOF
( cd "$PD" && "$BE" put .gitmodules ) >/dev/null 2>&1 || _fail "D: put .gitmodules"
_pinrow "vendor/sub" "$PD/.be/wtlog" "$STIP"
( cd "$PD" && "$BE" post '#mount sub' ) >/dev/null 2>&1 || _fail "D: mount post"
sleep 0.02
printf 'sub payload v2 EDITED\n' > "$PD/vendor/sub/lib.c"
( cd "$PD/vendor/sub" && "$BE" put lib.c ) >/dev/null 2>&1 || _fail "D: put lib.c in sub"
( cd "$PD" && "$BE" post '#bump sub' ) >"$WORK/postd.out" 2>"$WORK/postd.err" \
    || { cat "$WORK/postd.err"; _fail "D: top post"; }
STIP1=$(_subtip "$PD/vendor/sub")
[ "$STIP1" != "$STIP" ] || _fail "D: sub did not commit under the top post"
# lib.c only: helper.c was materialised by the mount `jab get`, which stamps
# nothing (GET-049, sibling ticket) — it is not a file this POST undirtied.
_chk -aged "$PD/vendor/sub" lib.c
_chk -aged "$PD" main.c .gitmodules
echo "ok   D. sub post + gitlink fold: sub interior + parent rows stamped, 0 reads"

echo "PASS [$NAME]"
