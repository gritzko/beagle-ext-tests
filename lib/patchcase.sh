# test/js/lib/patchcase.sh — differential parity harness for `bin/patch.js`
# (the pure-JS `be patch`, JS-052).  Sourced at the top of every
# test/js/patch/<case>/run.sh.  Each case builds ONE origin store with a
# trunk/feature divergence, forks an independent native and JS clone, runs
# `be patch <uri>` on each, then asserts byte-equivalence of the merged
# worktree, the `patch` ULOG row, and the file restamp (via `be` status).
#
# Self-contained (does NOT source test/lib/case.sh — this case sits 3 levels
# deep at test/js/patch/<case>).  POSIX sh.

set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)              # test/js/patch/<case>
_ROOT=$(cd "$_CASE/../.." && pwd)            # repo root
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "patchcase: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-$_BIN/jab}
# JAB-001: scripts live in the sibling `be/` submodule ($_ROOT/../be).
# GUARD: skip (exit 0) if that cross-submodule path is absent.
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "patchcase: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }
[ -x "$JABC" ] || { echo "patchcase: no jab at $JABC" >&2; exit 2; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"
export BE JABC PATCHJS

#  JS-052/DIS-051: pin the reproducible-build clock so the builder's `be post`
#  objects (and thus their shas, and the RGA/weave tie-break that decides the
#  conflict-fence SIDE ORDER) are stable run-to-run.  RONNow honours
#  SOURCE_DATE_EPOCH (abc/RON.c); jabc's ron.now() rides the same native path,
#  so the JS side pins identically.  Without it a conflict golden flips with
#  the wall-clock-driven commit shas (a TEST artifact, not a merge bug).
: "${SOURCE_DATE_EPOCH:=1467331200}"; export SOURCE_DATE_EPOCH   # 2016-07-01Z
: "${TZ:=UTC}"; export TZ

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/js-patch/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
# JS verbs run bareword (`jab <verb>`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sf "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
export WORK

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [$NAME]"; }

# strip the leading date col so two runs at different wall-clocks compare,
# and drop the native-only commit-line / stats-summary lines (cosmetic) so
# only the per-file status rows are diffed.  The VERB is field 2 (`T <verb>
# <path>`); match it as a whole field so a commit subject that merely contains
# a status word (e.g. `post ?h#f2 del X`) is NOT mistaken for a status row.
_normbanner() {
    sed -E 's/^ *[0-9]{1,2}:[0-9]{2} */T /' \
      | awk '$2=="applied"||$2=="merged"||$2=="conf"||$2=="del"||$2=="modl"||$2=="failed"||$2=="add"' \
      || true
}

# the last `patch` wtlog row, ts-normalised (store-backed wt: .be IS the wtlog).
_patch_row() {  # _patch_row WTDIR
    grep -a $'\tpatch\t' "$1/.be" 2>/dev/null | tail -1 | sed -E 's/^[^\t]*\t/T\t/'
}

# `be` status of a wt, date-normalised — proves the restamp (a patched file
# reads `pat`, not `mod`, iff its mtime == the patch row ts).
_status() {  # _status WTDIR
    ( cd "$1" && "$BE" 2>&1 ) | sed -E 's/^ *[0-9]{1,2}:[0-9]{2} */T /'
}

# --- patch_parity: fork native + JS clones of $ORG, patch each, assert -------
# Usage:  patch_parity ORIGIN_BUILDER PATCH_URI [FILES...]
#   ORIGIN_BUILDER  builds the origin store in $ORG (a fresh primary repo,
#                   leaving cur at the branch we patch INTO).
#   PATCH_URI       the `be patch` arg (`#<sha>` | `?<br>` | `?<br>!`); a
#                   literal `@F1` is expanded to the F1 sha the builder exports.
#   FILES           worktree files to byte-compare between the two clones.
# Builder must `export F1=...` (etc.) for any `@NAME` refs in PATCH_URI.
patch_parity() {
    _builder=$1; _uri=$2; shift 2
    ORG="$WORK/org"; mkdir -p "$ORG/.be"
    #  Run the builder in THIS shell (cd in a saved-pwd block, not a subshell)
    #  so any `export F1=...` it does survives for the `@NAME` expansion below.
    _opwd=$(pwd); cd "$ORG"; "$_builder"; cd "$_opwd"
    #  Expand `@NAME` → the env var NAME the builder exported.
    case "$_uri" in
        *@*) _ref=$(printf '%s' "$_uri" | sed -E 's/.*@([A-Za-z0-9_]+).*/\1/')
             _val=$(eval "printf '%s' \"\${$_ref}\"")
             _uri=$(printf '%s' "$_uri" | sed "s/@$_ref/$_val/") ;;
    esac

    NAT="$WORK/nat"; JS="$WORK/js"; mkdir -p "$NAT" "$JS"
    ( cd "$NAT" && "$BE" get "file://$ORG/.be?/org" >/dev/null 2>&1 ) || _fail "native clone failed"
    ( cd "$JS"  && "$BE" get "file://$ORG/.be?/org" >/dev/null 2>&1 ) || _fail "JS clone failed"

    ( cd "$NAT" && "$BE" patch "$_uri" ) >"$WORK/nat.out" 2>"$WORK/nat.err" \
        || _fail "native patch failed: $(cat "$WORK/nat.err")"
    ( cd "$JS" && "$JABC" patch "$_uri" ) >"$WORK/js.out" 2>"$WORK/js.err" \
        || _fail "JS patch failed: $(cat "$WORK/js.err")"

    #  1. merged worktree bytes — file-by-file byte equality (STILL native==JS:
    #     DIS-057 left the WEAVE merge engine + barrier row untouched).
    for f in "$@"; do
        if [ -e "$NAT/$f" ] || [ -e "$JS/$f" ]; then
            cmp -s "$NAT/$f" "$JS/$f" \
                || _fail "wt bytes differ for $f:
native: $(cat "$NAT/$f" 2>/dev/null | tr '\n' '.')
js:     $(cat "$JS/$f" 2>/dev/null | tr '\n' '.')"
        fi
    done

    #  2. the `patch` ULOG row (scope + sha), ts-normalised (STILL native==JS).
    nrow=$(_patch_row "$NAT"); jrow=$(_patch_row "$JS")
    [ "$nrow" = "$jrow" ] || _fail "patch row differs:
native: $nrow
js:     $jrow"

    #  DIS-057 — UNTIED from native here: the JS patch banner spells a conflict
    #  `cnf` (was `conf`) and `jab status` reads the patch-stamp OFFSET as
    #  pat/mrg/cnf, so it intentionally diverges from native `be`.  Checks 3 & 4
    #  are now JS-ONLY golden assertions against per-case fixtures:
    #    $EXPECT_BANNER  the patch banner's per-file status rows (one `<verb>
    #                    <path>` per line; the patch-verb vocabulary applied/
    #                    merged/cnf/del/modl), or unset to skip.
    #    $EXPECT_STATUS  the `jab status` buckets after the patch (one `<bucket>
    #                    <path>` per line, lex; the Dirty.mkd pat/mrg/cnf), or
    #                    unset to skip.  Both date-normalised → time-independent.

    #  3. JS banner per-file status rows == the committed golden.  The patch
    #     banner emits per-file rows with a BLANK date column, so the verb is the
    #     first field after the leading whitespace (`<verb> <path>`).
    if [ -n "${EXPECT_BANNER+x}" ]; then
        jban=$(grep -vE 'patch patch:' "$WORK/js.out" 2>/dev/null \
                 | sed -E 's/^ +//' \
                 | grep -E '^(applied|merged|cnf|del|modl|failed|add|mod) ')
        _exp=$(printf '%b' "$EXPECT_BANNER")
        [ "$jban" = "$_exp" ] || _fail "JS banner status rows != golden:
golden:
$_exp
js:
$jban"
    fi

    #  4. JS `jab status` buckets == the committed golden (the restamp proof: a
    #     clean apply reads `pat`, a merge `mrg`, a conflict `cnf`).
    if [ -n "${EXPECT_STATUS+x}" ]; then
        jst=$(_jstatus "$JS")
        _exp=$(printf '%b' "$EXPECT_STATUS")
        [ "$jst" = "$_exp" ] || _fail "jab status buckets != golden (restamp):
golden:
$_exp
js:
$jst"
    fi
}

# `jab status` of a wt, reduced to date-normalised `<bucket> <path>` rows (the
# header + summary stripped) — the JS-only restamp/classify golden (DIS-057).
_jstatus() {  # _jstatus WTDIR
    ( cd "$1" && "$JABC" status --plain 2>/dev/null ) \
      | sed -nE 's/^ *[0-9A-Za-z:]+ +([a-z]{3}) +(.*)$/\1 \2/p'
}

# --- patch_js_golden: JS patch one clone, assert the merged FILE bytes ---------
# against an explicit dog/WEAVE golden.  For the DOG-005 residual: native
# `be patch` (graf path) frames a conflict OURS-FIRST — it builds the base/ours
# weave, then lays theirs' tip on as ONE edit, so ours' tokens always precede
# theirs'.  dog's symmetric WEAVEMerge instead orders the two sides by the RGA
# commit-id tie-break (hash-order), which the maintainer has ruled CORRECT.  So
# on a true multi-commit same-anchor conflict native and JS legitimately differ
# on side ORDER until graf is retired (DOG-005); a pure native==JS differential
# would be asserting graf's soon-to-go behaviour.  Pin the clock (above) so the
# shas — and thus the dog order — are reproducible, then gate JS against that
# fixed dog golden.  Also confirms native is itself stable and that the ONLY
# divergence is the framed-side order (patch row + conf banner still match).
# Usage:  patch_js_golden ORIGIN_BUILDER PATCH_URI FILE GOLDEN
#   GOLDEN  expected merged FILE content, '\n' written literally as the 2-char
#           sequence  \n  (decoded with printf '%b').
patch_js_golden() {
    _builder=$1; _uri=$2; _file=$3; _golden=$4
    ORG="$WORK/org"; mkdir -p "$ORG/.be"
    _opwd=$(pwd); cd "$ORG"; "$_builder"; cd "$_opwd"
    case "$_uri" in
        *@*) _ref=$(printf '%s' "$_uri" | sed -E 's/.*@([A-Za-z0-9_]+).*/\1/')
             _val=$(eval "printf '%s' \"\${$_ref}\"")
             _uri=$(printf '%s' "$_uri" | sed "s/@$_ref/$_val/") ;;
    esac

    NAT="$WORK/nat"; JS="$WORK/js"; mkdir -p "$NAT" "$JS"
    ( cd "$NAT" && "$BE" get "file://$ORG/.be?/org" >/dev/null 2>&1 ) || _fail "native clone failed"
    ( cd "$JS"  && "$BE" get "file://$ORG/.be?/org" >/dev/null 2>&1 ) || _fail "JS clone failed"

    ( cd "$NAT" && "$BE" patch "$_uri" ) >"$WORK/nat.out" 2>"$WORK/nat.err" \
        || _fail "native patch failed: $(cat "$WORK/nat.err")"
    ( cd "$JS" && "$JABC" patch "$_uri" ) >"$WORK/js.out" 2>"$WORK/js.err" \
        || _fail "JS patch failed: $(cat "$WORK/js.err")"

    #  1. JS merged bytes == the deterministic dog golden (the gate).
    printf '%b' "$_golden" > "$WORK/golden"
    cmp -s "$WORK/golden" "$JS/$_file" \
        || _fail "JS merged bytes != dog golden for $_file:
golden: $(cat "$WORK/golden" | tr '\n' '.')
js:     $(cat "$JS/$_file" 2>/dev/null | tr '\n' '.')"

    #  2. the `patch` ULOG row still matches native (only side ORDER diverges).
    nrow=$(_patch_row "$NAT"); jrow=$(_patch_row "$JS")
    [ "$nrow" = "$jrow" ] || _fail "patch row differs:
native: $nrow
js:     $jrow"

    #  3. conf banner rows still match native.
    nban=$(_normbanner < "$WORK/nat.out"); jban=$(_normbanner < "$WORK/js.out")
    [ "$nban" = "$jban" ] || _fail "banner status rows differ:
native:
$nban
js:
$jban"

    #  4. DOG-005 marker: native frames the SAME conflict ours-first, so its
    #     bytes differ from JS's by side order alone — assert that residual is
    #     EXACTLY the order swap, not some other (real) merge divergence.  When
    #     graf retires and native adopts dog's order this cmp flips to equal and
    #     the case can fold back into patch_parity.
    if cmp -s "$NAT/$_file" "$JS/$_file"; then
        echo "NOTE [$NAME] native now byte-matches dog order (DOG-005 converged)" >&2
    fi
}
