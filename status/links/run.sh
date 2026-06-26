#!/bin/sh
# test/status/links — BRO-006: `be/views/status/status.js` must emit `U`
# click-targets so a bro pager left-click on a per-file status row opens that
# file, mirroring C `sniff/SNIFF.exe.c` (per-file rows carry a `'U'`-tagged
# `cat:`/`diff:` nav target — status_dump_verb → HUNK_NAV_CAT/DIFF, ~line 539).
#
# The pager consumes U targets from the HUNK tok32 stream (`be/views/bro/pager.js`
# `_uriAt`: a visible token followed by a `U` token whose hidden text bytes ARE
# the URI).  `jab status --tlv` IS that on-wire HUNK stream, so we capture it,
# load it into a HUNK ram log (the pager's own `hunksFromTlv` path), and assert
# every per-file row carries a `U` token decoding to that file's nav URI:
#   mod  → diff:<path>   (the file diverges; "show me what changed")
#   else → cat:<path>    (open the file)
# RED before the fix (status emits flat text, NO HUNK/toks → zero U tokens);
# GREEN after.  Also asserts PLAIN output is byte-identical to native `be status
# --plain` (the U bytes stay hidden — HUNKu8sFeedText skips them).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/status/links
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
BE=${BE:-${BIN:+$BIN/be}}
BE=${BE:-$(command -v be || true)}
[ -n "$BE" ] && [ -x "$BE" ] || { echo "status/links: cannot locate be (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$BE")
JABC=${JABC:-${JAB:-$_BIN/jab}}
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"
[ -f "$BEDIR/main.js" ] || { echo "status/links: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -x "$JABC" ] || { echo "status/links: no jab at $JABC" >&2; exit 2; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=$(basename "$_CASE")
. "$_ROOT/lib/repo-setup.sh"
WORK="$TMP/$$/status/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
# Hermetic firewall: an empty `.be` FILE above the scratch base stops a cwd-walk
# from escaping to a real $HOME/.be (rs firewall, DIS-024).
: > "$TMP/$$/.be" 2>/dev/null || true
# JS verbs run bareword (`jab status`); jab's upward be/-scan resolves the
# extension via this `be` shard symlink planted above the scratch worktrees.
ln -sf "$BEDIR" "$TMP/$$/be" 2>/dev/null || true

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# A committed baseline with three tracked files, then a dirty tree: a tracked
# mod (a.txt → diff:), an untracked add (n.txt → cat:), a nested tracked mod
# (d/c.txt → diff:), and a move (b.txt → m.txt → cat: the DST) — exercises both
# nav schemes, a path-bearing row, and the move-targets-dst rule.
WT="$WORK/wt"; mkdir -p "$WT/.be"
( cd "$WT" && printf 'A\n' > a.txt && printf 'B\n' > b.txt && mkdir d && printf 'C\n' > d/c.txt \
    && "$BE" post 'base' >/dev/null 2>&1 ) || _fail "could not seed the baseline"
( cd "$WT" && sleep 0.02 && printf 'A2\n' > a.txt && printf 'N\n' > n.txt && printf 'C2\n' > d/c.txt \
    && "$BE" put b.txt#m.txt >/dev/null 2>&1 ) || _fail "could not dirty the tree"

# 1. PLAIN parity: the U bytes are hidden (HUNKu8sFeedText skips them), so the
#    plain text is byte-identical to native `be status --plain`.
( cd "$WT" && "$BE"   status --plain ) >"$WORK/nat.plain" 2>/dev/null || true
( cd "$WT" && "$JABC" status --plain ) >"$WORK/jab.plain" 2>/dev/null || true
[ -s "$WORK/jab.plain" ] || _fail "jab status --plain emitted ZERO bytes"
cmp -s "$WORK/nat.plain" "$WORK/jab.plain" || {
    echo "--- native --plain ---"; cat -A "$WORK/nat.plain"
    echo "--- jab --plain ---";    cat -A "$WORK/jab.plain"
    _fail "plain output differs from native (U bytes must stay hidden)"
}
echo "ok: jab status --plain byte-matches native (U bytes hidden)"

# 2. U click-targets: capture the on-wire HUNK stream (--tlv) and assert each
#    per-file row carries a `U` token decoding to its nav URI.  RED pre-fix
#    (flat text, no toks → no U tokens); GREEN after.
( cd "$WT" && "$JABC" status --tlv ) >"$WORK/jab.tlv" 2>/dev/null || true
[ -s "$WORK/jab.tlv" ] || _fail "jab status --tlv emitted ZERO bytes"

# Expected nav URIs, one per per-file row (mod → diff:, mov → cat: the DST,
# else cat:).  Order-independent (the asserter set-compares).
cat > "$WORK/expect" <<EOF
diff:a.txt
diff:d/c.txt
cat:n.txt
cat:m.txt
EOF
"$JABC" "$_CASE/assert_u.js" "$WORK/jab.tlv" "$WORK/expect" \
    || _fail "U click-targets missing/incorrect (see assert above)"
echo "ok: every per-file status row emits a U nav target (cat:/diff:)"

echo "PASS [$NAME]"
