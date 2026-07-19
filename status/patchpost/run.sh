#!/bin/sh
# test/status/patchpost — STATUS-016: a `patch` row CONSUMED by a subsequent
# `post` must stop lighting the quad patch column (3rd char) and drop the
# `N patch` summary segment.  PATCH.mkd: the absorbed sha is recorded "for the
# next POST to consume", so ANY post (selective too) ends the patch scope — the
# old floor advanced only on a get / commit-all post, so a SELECTIVE post (a
# `put` staged before it) left the consumed patch's whole theirs tree still
# lighting the yellow column TWO posts on, on a byte-CLEAN tree (work/WORK-004).
#
#       R ── (feat: F1 sets fileA=a2)     wt tracks trunk@R, base=R
#  patch #F1 weaves fileA=a2 in (theirs), then `put fileA` + `post` SELECTIVELY
#  commits it: base advances to B(fileA=a2), track stays trunk@R, root=R.
#
#  PRE-post  (patch pending): fileA `..vv`, summary `1 patch, 1 wt`  (leg passes).
#  POST-post (patch consumed): fileA `.v..` (base advanced, patch CLEAR), summary
#  `1 base (ahead 1)` with NO patch segment, byte-parity with a never-patched wt.
#  Bystander fileC (untouched by F1, byte-equal to base) reads `....` at EVERY
#  stage.  RED before the fix (POST-post `.vv.` + `1 base, 1 patch`).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/status/patchpost
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "status/patchpost: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "status/patchpost: SKIP — no $BEDIR/main.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
#  Pin the clock so the F1 commit sha (and the weave tie-break) is reproducible.
: "${SOURCE_DATE_EPOCH:=1467331200}"; export SOURCE_DATE_EPOCH   # 2016-07-01Z
: "${TZ:=UTC}"; export TZ

: "${TMP:=/tmp}"; export TMP
NAME=patchpost
WORK="$TMP/$$/status/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [status/$NAME] $*" >&2; exit 1; }
# jab is ASAN — drop the rolling keeper.idx before each op so an earlier commit's
# fork-point object stays visible after a later post (patchcase.sh idiom).
_jab() { rm -f "$WT"/.be/*.keeper.idx 2>/dev/null || true; ( cd "$WT" && "$BE" "$@" ); }
_tip() { "$JABC" "$_ROOT/put/tipsha.js" "$WT"; }
# the quad rows, date-stripped to `<quad4> <path>` (header + summary dropped).
_rows() { ( cd "$WT" && "$JABC" status --plain 2>/dev/null ) \
    | sed -nE 's/^ *([0-9A-Za-z:]+ +)?([.xovXV!]{4}) +(.*)$/\2 \3/p'; }
# the summary line (`?<label>\t<segs>  (ahead/behind)`), tab-normalised.
_summ() { ( cd "$WT" && "$JABC" status --plain 2>/dev/null ) \
    | sed -nE 's/^[^	]*	(.*)$/\1/p' | head -1; }

# --- build ONE wt: trunk@R with fileA/B/C, feat forks at R and sets fileA=a2 --
# $1 = wt dir, $2 = 1 (patch #F1) | 0 (never-patched: hand-set fileA=a2).
build_wt() {
    WT="$1"; mkdir -p "$WT/.be"
    printf 'a1\n' > "$WT/fileA.txt"
    printf 'b1\n' > "$WT/fileB.txt"
    printf 'c1\n' > "$WT/fileC.txt"
    _jab post 'R base' >/dev/null 2>&1 || _fail "seed R"
    R=$(_tip); [ -n "$R" ] || _fail "no R tip"
    _jab post '?' >/dev/null 2>&1 || _fail "mint trunk@R"          # trunk ref = R
    _jab put '?feat' >/dev/null 2>&1 || _fail "fork feat"
    _jab get '?feat' >/dev/null 2>&1 || _fail "switch feat"
    printf 'a2\n' > "$WT/fileA.txt"
    _jab put fileA.txt >/dev/null 2>&1 || _fail "stage F1"
    _jab post 'F1 fileA=a2' >/dev/null 2>&1 || _fail "commit F1"
    _jab post '?feat' >/dev/null 2>&1 || _fail "publish feat"
    F1=$(_tip); [ -n "$F1" ] || _fail "no F1 tip"
    _jab get "?#$R" >/dev/null 2>&1 || _fail "back to trunk@R"     # base=R, track=trunk@R
}

WT="$WORK/patched"
build_wt "$WT" 1

# ---- PRE-post: patch #F1 pending → fileA lights the patch column -------------
_jab patch "#$F1" >/dev/null 2>&1 || _fail "patch #F1"
_rows > "$WORK/pre.rows"
grep -q '^\.\.vv fileA\.txt$' "$WORK/pre.rows" || {
    echo "--- PRE-post rows ---"; cat "$WORK/pre.rows"; _summ
    _fail "PRE-post: fileA not '..vv' (patch pending should light patch+wt)"
}
grep -qE 'file[BC]\.txt' "$WORK/pre.rows" && {
    echo "--- PRE-post rows ---"; cat "$WORK/pre.rows"
    _fail "PRE-post: an untouched bystander (fileB/fileC) leaked a row"
}
case "$(_summ)" in *"patch"*) ;; *) _fail "PRE-post: summary lost the 'patch' segment: $(_summ)" ;; esac
echo "ok   PRE-post: pending patch lights fileA '..vv', bystanders '....'"

# ---- POST-post: a SELECTIVE post (put then post) CONSUMES the patch ----------
_jab put fileA.txt >/dev/null 2>&1 || _fail "stage fileA"
_jab post 'consume patch' >/dev/null 2>&1 || _fail "selective post"
# byte-clean tree (the incident's premise): jab diff must be empty.
( cd "$WT" && "$JABC" diff 2>/dev/null | grep -q . ) && _fail "POST-post: tree not byte-clean (diff non-empty)"
_rows > "$WORK/post.rows"
# fileA: base advanced (`.v..`), patch column CLEAR — NOT `.vv.`.
grep -q '^\.v\.\. fileA\.txt$' "$WORK/post.rows" || {
    echo "--- POST-post rows ---"; cat "$WORK/post.rows"; _summ
    _fail "POST-post: fileA not '.v..' — patch column still lit after the consuming post"
}
grep -qE 'file[BC]\.txt' "$WORK/post.rows" && {
    echo "--- POST-post rows ---"; cat "$WORK/post.rows"
    _fail "POST-post: a bystander (fileB/fileC) leaked a row"
}
# summary: `1 base`, the (ahead 1) note, and NO patch segment.
_ps=$(_summ)
case "$_ps" in *"patch"*) _fail "POST-post: summary still carries a 'patch' segment: $_ps" ;; esac
case "$_ps" in *"1 base"*) ;; *) _fail "POST-post: summary lost '1 base': $_ps" ;; esac
case "$_ps" in *"ahead 1"*) ;; *) _fail "POST-post: summary lost '(ahead 1)': $_ps" ;; esac
echo "ok   POST-post: consumed patch clears the column + summary segment"

# ---- byte-parity with a never-patched, equivalently-committed wt -------------
WT2="$WORK/plain"
build_wt "$WT2" 0
printf 'a2\n' > "$WT2/fileA.txt"
( rm -f "$WT2"/.be/*.keeper.idx 2>/dev/null || true; cd "$WT2" && "$BE" put fileA.txt >/dev/null 2>&1 ) || _fail "plain stage"
( rm -f "$WT2"/.be/*.keeper.idx 2>/dev/null || true; cd "$WT2" && "$BE" post 'plain commit' >/dev/null 2>&1 ) || _fail "plain post"
WT_SAVE=$WT; WT=$WT2; _rows > "$WORK/plain.rows"; WT=$WT_SAVE
# same quad rows (paths + quads), ignoring the differing commit-row sha/subject.
_norm() { sed -E 's/\?[0-9a-f]+#.*$/?COMMIT/'; }
diff <(_norm < "$WORK/post.rows") <(_norm < "$WORK/plain.rows") >/dev/null || {
    echo "--- patched ---"; cat "$WORK/post.rows"; echo "--- never-patched ---"; cat "$WORK/plain.rows"
    _fail "POST-post: patched wt not byte-par with a never-patched wt"
}
echo "ok   POST-post: byte-parity with the never-patched wt"

echo "PASS [status/$NAME]"
