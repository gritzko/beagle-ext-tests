#!/bin/sh
# test/ls/links — BRO-006: the `ls:` / `lsr:` / `tree:` listing VIEWs
# (`be/views/{ls,lsr,tree}/*.js`) must emit `U` click-targets so a bro pager
# left-click on an entry row opens that entry — mirroring C `sniff/LS.c` (each
# row carries a `'U'`-tagged nav URI: `cat:<path>` for a file, `ls:<sub>/` for a
# dir; tree mirrors native `be tree:` — `blob:<path>` / `tree:<path>/`).
#
# The pager consumes U targets from the HUNK tok32 stream (`be/views/bro/pager.js`
# `_uriAt`: a visible token immediately followed by a `U` token whose hidden text
# bytes ARE the URI).  `jab <verb> --tlv` IS that on-wire HUNK stream, so we
# capture it, walk it the pager's `hunksFromTlv` way, and assert every entry row
# carries a `U` token decoding to that entry's nav URI.  RED before the fix (the
# views emit flat columnar text, NO HUNK toks → zero U tokens); GREEN after.
# Also asserts PLAIN output is byte-identical to native `--plain` (the U bytes
# stay hidden — HUNKu8sFeedText skips them).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/ls/links
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "ls/links: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-${JAB:-$_BIN/jab}}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "ls/links: SKIP — no $BEDIR/main.js" >&2; exit 0; }
{ [ -f "$BEDIR/views/ls/ls.js" ] || [ -f "$BEDIR/verbs/ls/ls.js" ]; } \
    || { echo "ls/links: SKIP — no {views,verbs}/ls/ls.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "ls/links: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/ls/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall: an empty `.be` FILE above the scratch base stops a cwd-walk
# from escaping to a real $HOME/.be (rs firewall, DIS-024).
: > "$TMP/$$/.be" 2>/dev/null || true
# JS verbs run bareword (`jab ls`); jab's upward be/-scan resolves the extension
# via this `be` shard symlink planted above the scratch worktrees.
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# A committed baseline: two tracked files at root + a tracked file in `sub/`, so
# the listing has both a file row (→ cat:/blob:) and a dir row (→ ls:/tree:).
WT="$WORK/wt"; mkdir -p "$WT/.be"
( cd "$WT" && printf 'A\n' > a.txt && printf 'B\n' > b.txt \
    && mkdir sub && printf 'S\n' > sub/s.txt \
    && "$BE" post 'base' >/dev/null 2>&1 ) || _fail "could not seed the baseline"

# assert PLAIN parity then capture --tlv and assert U targets.
#   $1 desc  $2 jab-verb  $3 uri  $4 plain-mode (`eq`=byte-cmp vs native $5 |
#   `nonempty`=just non-empty, $5 unused for scoped views whose JS names render
#   RELATIVE to scope — a separate, already-tested divergence)  $5 native-uri
#   $6..  expected nav URIs.
_check() {
    _desc=$1; _verb=$2; _uri=$3; _pmode=$4; _natu=$5; shift 5
    rm -f "$WT/.be/queue" 2>/dev/null || true
    # 1. PLAIN: the U bytes stay hidden (HUNKu8sFeedText skips them) — so plain
    #    is byte-identical to native at root scope (relative == full path there).
    ( cd "$WT" && "$JABC" "$_verb" "$_uri" --plain ) >"$WORK/jab.plain" 2>/dev/null || true
    [ -s "$WORK/jab.plain" ] || _fail "$_desc: jab $_verb --plain emitted ZERO bytes"
    if LC_ALL=C grep -q "$(printf '\033')" "$WORK/jab.plain"; then
        echo "--- jab plain ---"; cat -A "$WORK/jab.plain"
        _fail "$_desc: --plain carries an SGR/U escape (U bytes must stay hidden)"
    fi
    if [ "$_pmode" = "eq" ]; then
        ( cd "$WT" && "$BE" "$_natu" --plain ) >"$WORK/nat.plain" 2>/dev/null || true
        cmp -s "$WORK/nat.plain" "$WORK/jab.plain" || {
            echo "--- native $_natu --plain ---"; cat -A "$WORK/nat.plain"
            echo "--- jab $_verb $_uri --plain ---"; cat -A "$WORK/jab.plain"
            _fail "$_desc: plain output differs from native (U bytes must stay hidden)"
        }
    fi
    # 2. U click-targets from the on-wire --tlv HUNK stream.
    rm -f "$WT/.be/queue" 2>/dev/null || true
    ( cd "$WT" && "$JABC" "$_verb" "$_uri" --tlv ) >"$WORK/jab.tlv" 2>/dev/null || true
    [ -s "$WORK/jab.tlv" ] || _fail "$_desc: jab $_verb --tlv emitted ZERO bytes"
    : > "$WORK/expect"
    for _e in "$@"; do echo "$_e" >> "$WORK/expect"; done
    "$JABC" "$_CASE/assert_u.js" "$WORK/jab.tlv" "$WORK/expect" \
        || _fail "$_desc: U click-targets missing/incorrect (see assert above)"
    echo "ok: $_desc — plain stable (U hidden) + every row emits a U nav target"
}

# URI-014: ls/lsr U-targets + banners are now the `word URI` spell (`cat a.txt`,
# `ls sub/`) — the verb OUT of the scheme.  Native still bakes `ls:` banners (C
# follow-up), so the plain banner DIVERGES from native → assert plain is stable
# (`nonempty`), not native byte-equal.  tree: below is unchanged (native-parity).
# ls: root — file rows → `cat <path>`, the subdir row → `ls <sub>/`.
_check "ls: root"  ls  "ls:"      nonempty "ls:"      "cat a.txt" "cat b.txt" "ls sub/"
# ls:sub/ — the scoped file row → `cat <full-path>` (re-openable by the pager).
_check "ls:sub/"   ls  "ls:sub/"  nonempty "ls:sub/"  "cat sub/s.txt"
# lsr: — per-dir hunks (BFS): root (cat a/cat b/ls sub/) then sub/ (cat sub/s).
_check "lsr:"      lsr "lsr:"      nonempty "ls:"      "cat a.txt" "cat b.txt" "ls sub/" "cat sub/s.txt"
# URI-014: tree U-targets/banners are the `word URI` spell too (`blob <path>`,
# `tree <sub>/`); its banner diverges from native's `tree:` (C follow-up) so the
# plain check is `nonempty`, not native-equal.
# tree: root — blob rows → `blob <path>`, the subdir → `tree <sub>/`.
_check "tree:"     tree "tree:"    nonempty "tree:"    "blob a.txt" "blob b.txt" "tree sub/"
# tree:sub/ — the scoped blob → `blob <full-path>` (the `..` row carries NO U).
_check "tree:sub/" tree "tree:sub/" nonempty "tree:sub/" "blob sub/s.txt"

echo "PASS [$NAME]"
