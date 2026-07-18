# test/lib/patchspec.sh — harness for the SPEC-FIRST test/patch/<case> set
# (PATCH.mkd rulings 2026-07-17: line absorb, picked/foster provenance,
# path-scoped, noop-behind).  SELF-CONTAINED on purpose: patchcase.sh is
# concurrently owned by the golden-parity rework — this file only borrows its
# idioms (jab-only DAG seeding, pid scratch, keeper.idx drop).  POSIX sh.

set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)              # test/patch/<case>
_ROOT=$(cd "$_CASE/../.." && pwd)                 # test/
# TEST-003: jab-only — native `be` is RETIRED; alias BE=$JABC.
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "patchspec: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "patchspec: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }
case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

#  Pin the reproducible-build clock (DIS-051) so builder shas are stable.
: "${SOURCE_DATE_EPOCH:=1467331200}"; export SOURCE_DATE_EPOCH   # 2016-07-01Z
: "${TZ:=UTC}"; export TZ

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
WORK="$TMP/$$/js-patchspec/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
#  jab's upward scan resolves bareword verbs via this jsrc shard symlink.
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
#  PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT
export WORK BE JABC BEDIR

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [$NAME]"; }

#  TEST-003 jab-only DAG seeding (the patchcase.sh idioms).  The rolling
#  keeper.idx indexes only the LATEST keeper — drop it before each op.
_jab() { rm -f .be/*.keeper.idx 2>/dev/null; "$BE" "$@"; }
#  DIS-076: a bare post never moves a ref — the wt's OWN cur is the only tip.
_orgtip() { ( cd "$1" && "$JABC" refs 2>/dev/null ) | sed -n 's/^cur: *//p'; }
_orgbranch() { ( cd "$1" && "$JABC" refs 2>/dev/null ) | sed -n 's/^branch: *?//p'; }
#  _boot MSG: FIRST commit on a fresh repo — post ALONE auto-adds the wt.
_boot() { _jab post "$1" >/dev/null 2>&1; BOOT=$(_orgtip .); }
_fork() { _jab put "?$1" >/dev/null 2>&1; }                   # label-only fork
_sw() { _jab get "?$1" >/dev/null 2>&1; }                     # switch wt to BR
_trunk() { _jab get "?#$BOOT" >/dev/null 2>&1; }              # back by PINNED t0
#  _ci MSG FILE...: stage + commit + republish the current branch's ref.
_ci() {
    _msg=$1; shift
    _jab put "$@" >/dev/null 2>&1
    _jab post "$_msg" >/dev/null 2>&1
    _br=$(_orgbranch .); _jab post "?$_br" >/dev/null 2>&1
}
_tip() { _orgtip .; }

#  `jab status` reduced to `<bucket> <path>` rows (header/summary stripped).
_jstatus() { ( cd "$1" && "$JABC" status --plain 2>/dev/null ) \
    | sed -nE 's/^ *[0-9A-Za-z:]+ +([a-z]{3}) +(.*)$/\1 \2/p'; }

#  The `patch` wtlog rows, ts-normalised: a store-backed wt's `.be` IS the
#  wtlog FILE; a primary wt keeps it at `.be/wtlog`.
#  ps_patch_rows WT — ALL rows; ps_patch_row WT — the last.
ps_patch_rows() {
    _w="$1/.be"; [ -d "$_w" ] && _w="$_w/wtlog"
    grep -a $'\tpatch\t' "$_w" 2>/dev/null | sed -E 's/^[^\t]*\t/T\t/'
}
ps_patch_row() { ps_patch_rows "$1" | tail -1; }

#  ps_clone DST — clone a JS worktree of $ORG pinned at ORG's own cur tip.
ps_clone() {
    rm -f "$ORG"/.be/*.keeper.idx 2>/dev/null
    _t=$(_orgtip "$ORG")
    mkdir -p "$1"
    ( cd "$1" && "$BE" get "file://$ORG/.be#$_t" >/dev/null 2>&1 ) \
        || _fail "clone of $ORG failed"
}

#  ps_commit WT [SHA] — dump the RAW commit object body (headers + message) of
#  WT's cur tip (or SHA) to stdout: the parent/picked/foster header oracle.
ps_commit() {
    cat > "$WORK/.commit.js" <<'EOF'
const be    = require(process.argv[2] + "/core/discover.js");
const store = require(process.argv[2] + "/shared/store.js");
const wtlog = require(process.argv[2] + "/shared/wtlog.js");
const info  = be.treeAt(process.argv[3]);
const reader = store.open(info.storePath, info.project);
let sha = process.argv[4] || "";
if (!sha) { const cur = wtlog.open(info).curTip(); sha = (cur && cur.sha) || ""; }
const obj = sha && reader.getObject(sha);
if (obj) { const b = io.buf(obj.bytes.length + 8); b.feed(obj.bytes); io.writeAll(1, b); }
EOF
    "$JABC" "$WORK/.commit.js" "$BEDIR" "$1" "${2:-}" 2>/dev/null
}

#  ps_parents WT — the cur tip commit's `parent` shas, one per line.
ps_parents() { ps_commit "$1" | sed -n 's/^parent //p'; }
