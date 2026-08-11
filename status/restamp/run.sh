#!/bin/sh
# test/status/restamp — STATUS-022: `status!` RESTAMPS what its classify
# content-hashed and proved equal to base; plain `status` never does.
#
# Plain `status` stays the pure reader [DIS-023]/[STATUS-011]: it content-hashes
# a clean-but-unstamped file on EVERY run and writes nothing.  The verb-bang
# `status!` (core/loop.js:381 sheds `!`, raises be.force) additionally sets each
# CONTENT-CONFIRMED clean file's mtime to this wt's latest get/post row ts
# (`wtlogReader.boundaries().pd`) — no wtlog row, no printed word, idempotent —
# so the sweep of re-hashes ends for that wt ([STATUS-021]).
#
# Asserted here, on one seeded wt (a.txt/b.txt clean-but-scuffed, d.txt a real
# local edit, link.lnk a tracked symlink pointing AT d.txt):
#   1. plain `status` leaves every mtime alone (the reader invariant);
#   2. `status!` stamps a.txt/b.txt to EXACTLY the post row ts (in the stamp-set,
#      == boundaries().pd) and the next classify content-reads neither;
#   3. the dirty d.txt is never stamped, and its `mod` row survives — the
#      symlink is SKIPPED (io.setMtime FOLLOWS a link, so stamping link.lnk
#      would launder the dirty d.txt into the stamp-set: get.js:1099 precedent);
#   4. `status!` prints exactly what `status` prints, before and after;
#   5. a second `status!` restamps nothing (idempotent).
# RED on pristine status.js: a.txt/b.txt stay scuffed (NOSTAMP + READ).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/status/restamp
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${JAB:-${BIN:+$BIN/jab}}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "status/restamp: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "status/restamp: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/status/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall + the jsrc shard symlink (jab's upward jsrc-scan resolves the
# JS verbs from the worktree under test, above the scratch fixtures).
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [status/$NAME] $*" >&2; exit 1; }

# `_scuff FILE...` back-dates each file to a pid-derived 2023 epoch second — far
# below any wtlog row ts, so the mtime is NOT in the stamp-set and classify MUST
# content-hash the file to call it clean.  Content is untouched.  `-h` so a
# symlink's OWN mtime moves, never its target's (the POST-037 _scuff idiom).
_SCUFF_N=0
_scuff() {
    for f in "$@"; do
        _SCUFF_N=$((_SCUFF_N + 1))
        _t=$((1670000000 + ($$ * 7919 + _SCUFF_N * 104729) % 30000000))
        touch -h -d "@$_t" "$f" || _fail "touch -d failed on $f"
    done
}
_mt() { "$JABC" "$WORK/.mt.js" "$WT/$1" 2>/dev/null; }

# --- the STATUS-022 invariant checker ----------------------------------------
# jab .chk.js BEDIR WT +stamped... -unstamped...   — for each `+rel`: mtime ∈
# wtl.has() AND == boundaries().pd (the row ts EXACTLY, never a DIS-057 band
# slot), and ONE classify run (the status.js call shape, io.open hooked) opens
# none of them.  For each `-rel`: mtime must NOT be in the stamp-set.  The dirty
# row set must be exactly d.txt (nothing laundered clean).
cat > "$WORK/.chk.js" <<'EOF'
const bedir = process.argv[2], wt = process.argv[3];
const args  = process.argv.slice(4);
const discover = require(bedir + "/core/discover.js");
const wtlog    = require(bedir + "/shared/wtlog.js");
const store    = require(bedir + "/shared/store.js");
const classify = require(bedir + "/shared/classify.js");
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
const info = discover.treeAt(wt);
const wtl  = wtlog.open(info);          // THE reader status.js uses
const k    = store.open(info.storePath, info.project);
const pd   = wtl.boundaries().pd;       // the latest get/post row ts
const want = [], nope = [], bad = [];
for (const a of args) (a[0] === "+" ? want : nope).push(a.slice(1));
for (const rel of want) {
  let m;
  try { m = io.lstat(info.wt + "/" + rel).mtime; }
  catch (e) { bad.push("NOFILE " + rel); continue; }
  if (!wtl.has(m))  bad.push("NOSTAMP " + rel + " mtime=" + ron.encode(m));
  else if (m !== pd) bad.push("NOTROWTS " + rel + " mtime=" + m + " pd=" + pd);
}
for (const rel of nope) {
  let m;
  try { m = io.lstat(info.wt + "/" + rel).mtime; }
  catch (e) { bad.push("NOFILE " + rel); continue; }
  if (wtl.has(m)) bad.push("FALSESTAMP " + rel + " mtime=" + ron.encode(m));
}
const opened = [], realOpen = io.open;
io.open = function (p) { opened.push(String(p)); return realOpen.apply(io, arguments); };
let res;
try { res = classify.classify(info, wtl, k); } finally { io.open = realOpen; }
for (const rel of want) {
  const full = info.wt + "/" + rel;
  for (const p of opened) if (p === full) { bad.push("READ " + rel); break; }
}
const dirty = res.rows.map(function (r) { return r.bucket + " " + r.path; }).sort();
if (dirty.join(",") !== "mod d.txt")
  bad.push("ROWS [" + dirty.join(", ") + "] != [mod d.txt]");
if (bad.length) { w("chk FAIL " + wt + "\n" + bad.join("\n") + "\n");
                  throw "chk: " + bad.length + " violation(s)"; }
w("chk ok " + wt + " (" + want.length + " stamped == pd, 0 reads)\n");
EOF
cat > "$WORK/.mt.js" <<'EOF'
function w(s){const u=utf8.Encode(s);const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w(String(io.lstat(process.argv[2]).mtime) + "\n");
EOF

# --- the fixture -------------------------------------------------------------
WT="$WORK/wt"; mkdir -p "$WT/.be"
( cd "$WT" && printf 'A\n' > a.txt && printf 'B\n' > b.txt && printf 'D\n' > d.txt \
    && ln -s d.txt link.lnk && "$BE" post 'base' >/dev/null 2>&1 ) \
    || _fail "could not seed the baseline"
# a.txt/b.txt/link.lnk: CLEAN but off the stamp-set (the STATUS-021 cold-frame
# state); d.txt: a real local edit that must stay `mod` and stay unstamped.
( cd "$WT" && printf 'D2\n' > d.txt ) || _fail "could not dirty d.txt"
_scuff "$WT/a.txt" "$WT/b.txt" "$WT/link.lnk"
A0=$(_mt a.txt); B0=$(_mt b.txt); L0=$(_mt link.lnk); D0=$(_mt d.txt)

# 1. plain `status` is a PURE READER — it hashes a.txt/b.txt and writes nothing.
( cd "$WT" && "$JABC" status --plain ) >"$WORK/o1" 2>"$WORK/o1.err" \
    || _fail "plain status failed: $(cat "$WORK/o1.err")"
[ "$(_mt a.txt)" = "$A0" ] || _fail "plain status RESTAMPED a.txt (DIS-023: status is a reader)"
[ "$(_mt b.txt)" = "$B0" ] || _fail "plain status RESTAMPED b.txt (DIS-023: status is a reader)"

# 2. `status!` — the restamp, silent.
( cd "$WT" && "$JABC" 'status!' --plain ) >"$WORK/o2" 2>"$WORK/o2.err" \
    || _fail "status! failed: $(cat "$WORK/o2.err")"
[ -s "$WORK/o2.err" ] && { cat "$WORK/o2.err" >&2; _fail "status! wrote to stderr"; }
"$JABC" "$WORK/.chk.js" "$BEDIR" "$WT" +a.txt +b.txt -d.txt -link.lnk \
    || _fail "the STATUS-022 invariant is broken (see chk above)"
[ "$(_mt link.lnk)" = "$L0" ] || _fail "status! stamped the SYMLINK link.lnk (setMtime follows links)"
[ "$(_mt d.txt)"    = "$D0" ] || _fail "status! stamped the DIRTY d.txt (or laundered it via link.lnk)"

# 3. output parity: `status!` prints what `status` prints, and the next plain
#    `status` still prints it (the `mod d.txt` row survives the restamp).
( cd "$WT" && "$JABC" status --plain ) >"$WORK/o3" 2>/dev/null || true
norm() { sed 's/[0-9][0-9]:[0-9][0-9]/TT:TT/g'; }
norm <"$WORK/o1" >"$WORK/o1.n"; norm <"$WORK/o2" >"$WORK/o2.n"; norm <"$WORK/o3" >"$WORK/o3.n"
cmp -s "$WORK/o1.n" "$WORK/o2.n" || {
    echo "--- status ---"; cat "$WORK/o1" >&2; echo "--- status! ---"; cat "$WORK/o2" >&2
    _fail "status! output != status output (the restamp must be SILENT)"; }
cmp -s "$WORK/o1.n" "$WORK/o3.n" || {
    echo "--- status (before) ---"; cat "$WORK/o1" >&2
    echo "--- status (after) ---";  cat "$WORK/o3" >&2
    _fail "status changed after status! (a row was lost — something was laundered)"; }

# 4. idempotent: a second `status!` has nothing left to confirm-and-stamp.
A1=$(_mt a.txt); B1=$(_mt b.txt)
( cd "$WT" && "$JABC" 'status!' --plain ) >"$WORK/o4" 2>/dev/null || _fail "2nd status! failed"
[ "$(_mt a.txt)" = "$A1" ] || _fail "2nd status! moved a.txt (not idempotent)"
[ "$(_mt b.txt)" = "$B1" ] || _fail "2nd status! moved b.txt (not idempotent)"
[ "$(_mt link.lnk)" = "$L0" ] || _fail "2nd status! moved link.lnk"
[ "$(_mt d.txt)"    = "$D0" ] || _fail "2nd status! moved d.txt"
norm <"$WORK/o4" >"$WORK/o4.n"
cmp -s "$WORK/o1.n" "$WORK/o4.n" || _fail "2nd status! output drifted"
echo "ok: status! stamped 2 content-confirmed files to the post row ts, idempotent"

echo "PASS [status/$NAME]"
