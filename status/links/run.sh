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
ln -sfn "$BEDIR" "$TMP/$$/be" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [$NAME] $*" >&2; exit 1; }

# A committed baseline with four tracked files, then a dirty tree exercising
# EVERY nav scheme + bucket:
#   a.txt    → mod  (base present, edited)       → diff: (wt-vs-base)
#   d/c.txt  → mod  (nested base present, edited)→ diff:
#   r.txt    → del  (staged delete, base present)→ diff: (deletion diff)
#   k.txt    → mis  (base present, rm'd off disk)→ diff: (deletion diff)
#   n.txt    → unk  (untracked add, no base)     → cat:
#   b.txt→m.txt move — DIS-057 Dirty.mkd PAIR:
#     rmv b.txt (source, base present, removed)  → diff: (deletion diff; move-row
#                                                  nav restored)
#     mov m.txt (dest, no base, new content)     → cat:
# DIS-057 NAV RULE: a base-present row (mod/put/pat/mrg/cnf, and the gone-from-wt
# rmv/del/mis) leads to a `diff:` (wt-vs-base, or base-vs-empty deletion diff);
# a base-less / new-content row (new/unk/mov/adv) keeps `cat:`.
WT="$WORK/wt"; mkdir -p "$WT/.be"
( cd "$WT" && printf 'A\n' > a.txt && printf 'B\n' > b.txt && mkdir d && printf 'C\n' > d/c.txt \
    && printf 'R\n' > r.txt && printf 'K\n' > k.txt \
    && "$BE" post 'base' >/dev/null 2>&1 ) || _fail "could not seed the baseline"
( cd "$WT" && sleep 0.02 && printf 'A2\n' > a.txt && printf 'N\n' > n.txt && printf 'C2\n' > d/c.txt \
    && "$BE" put b.txt#m.txt >/dev/null 2>&1 \
    && "$BE" delete r.txt >/dev/null 2>&1 \
    && rm -f k.txt ) || _fail "could not dirty the tree"

# 1. PLAIN output: the U bytes are hidden (HUNKu8sFeedText skips them), so the
#    plain text carries only the visible columns.  DIS-057 UNTIES this from
#    native `be status --plain` (native still COLLAPSES the move to one `mov
#    b.txt#m.txt` row; JS now shows the Dirty.mkd `rmv`+`mov` PAIR), so assert the
#    date-normalised `<bucket> <path>` rows against the JS-only golden instead of
#    a native cmp.  Render order: put,new,rmv,mov,mod,… (ROW_ORDER).
( cd "$WT" && "$JABC" status --plain ) >"$WORK/jab.plain" 2>/dev/null || true
[ -s "$WORK/jab.plain" ] || _fail "jab status --plain emitted ZERO bytes"
# Drop the fixed 8-char leading date column (7-col date + 1 sep — a real ts, or
# 8 spaces for a ts-less `mis` row), then read `<verb> <path>` from each per-file
# row.  The `status:` banner (7 chars, no col) + the `?<branch>\t<counts>`
# summary don't match the `^.{8}<verb> ` shape, so they drop out naturally.
jrows=$(sed -nE 's/^.{8}([a-z]{3}) (.*)$/\1 \2/p' "$WORK/jab.plain")
exprows='rmv b.txt
mov m.txt
mod a.txt
mod d/c.txt
del r.txt
mis k.txt
unk n.txt'
[ "$jrows" = "$exprows" ] || {
    echo "--- jab --plain ---"; cat -A "$WORK/jab.plain"
    _fail "plain rows != DIS-057 golden:
golden:
$exprows
js:
$jrows"
}
echo "ok: jab status --plain shows the DIS-057 rmv/mov pair (U bytes hidden)"

# 2. U click-targets: capture the on-wire HUNK stream (--tlv) and assert each
#    per-file row carries a `U` token decoding to its nav URI.  RED pre-fix
#    (flat text, no toks → no U tokens); GREEN after.
( cd "$WT" && "$JABC" status --tlv ) >"$WORK/jab.tlv" 2>/dev/null || true
[ -s "$WORK/jab.tlv" ] || _fail "jab status --tlv emitted ZERO bytes"

# Expected nav URIs, one per per-file row.  DIS-057 NAV RULE: a base-present row
# (mod, plus the gone-from-wt rmv/del/mis) → diff:<path> (a wt-vs-base diff, or a
# base-vs-empty deletion diff); a base-less / new-content row (mov dest, unk) →
# cat:<path>.  The move PAIR is two rows — `rmv b.txt` → diff:b.txt (the deletion
# diff; move-row nav RESTORED) and `mov m.txt` → cat:m.txt.  Order-independent
# (the asserter set-compares).
cat > "$WORK/expect" <<EOF
diff:a.txt
diff:d/c.txt
diff:b.txt
diff:r.txt
diff:k.txt
cat:n.txt
cat:m.txt
EOF
"$JABC" "$_CASE/assert_u.js" "$WORK/jab.tlv" "$WORK/expect" \
    || _fail "U click-targets missing/incorrect (see assert above)"
echo "ok: every per-file status row emits a U nav target (cat:/diff:)"

echo "PASS [$NAME]"
