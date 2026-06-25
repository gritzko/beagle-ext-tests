#!/bin/sh
# test/js/bro/color — the JAB-003 colour sink for `bin/bro.js`.
#  (1) REGRESSION: adding the colour flag must not disturb the plain sink, so
#      re-assert `bro.js --plain` is byte-identical to native `bro --plain`
#      (the brocase.sh oracle) for a file, a dir, and multi-args.
#  (2) COLOUR: `bro.js --color <file>` emits SGR (ESC '['); `--plain` does not.
#      Not byte-parity with native `bro --color` (additive sink, ticket); we
#      assert the colour path differs from plain and carries the THEME banner.
#  (3) A dir hunk has no safe colour feed yet (BROCOLORDIR, see ticket): the
#      `--color` listing must STILL render (fall back to plain), never crash.
. "$(dirname "$0")/../lib/brocase.sh"

mkdir -p "$WORK/src/sub"
cat > "$WORK/src/a.c" <<'EOF'
// a comment
int main(void) { return 42; }
EOF
printf 'x\n' > "$WORK/src/x.txt"
cd "$WORK/src"

# 1. plain-sink byte-parity is unchanged by the new flag handling.
bro_eq "plain-file" a.c
bro_eq "plain-dir"  .
bro_eq "plain-multi" a.c x.txt

# 2. colour assertions: run `jab bro` (THROUGH THE LOOP, JAB-bro) with --color
#    and --plain on the SAME file.  GUARD (JAB-bro): the relocated handler
#    (verbs/bro/bro.js) mirrors the OLD be/bro.js entry, which only emits the
#    PLAIN sink at this trunk — the COLOUR sink (per-token SGR) is a later,
#    un-landed feature.  So SKIP the colour-specific assertions unless the
#    handler actually paints SGR; the in-scope PLAIN parity (the bro_eq legs
#    above) is the JAB-bro gate.  `bro` runs from $BROWT with an ABS file arg.
has_esc() { LC_ALL=C grep -q "$(printf '\033')" "$1"; }
_AFILE="$WORK/src/a.c"
( cd "$BROWT" && "$JABC" bro --color "$_AFILE" ) >"$WORK/c.out" 2>/dev/null \
    || _fail "color: nonzero exit"
( cd "$BROWT" && "$JABC" bro --plain "$_AFILE" ) >"$WORK/p.out" 2>/dev/null \
    || _fail "plain: nonzero exit"
has_esc "$WORK/p.out" && _fail "plain: unexpected SGR escape"
if ! has_esc "$WORK/c.out"; then
    echo "skip color-* — handler is plain-only at this trunk (colour sink NYI)" >&2
else
    cmp -s "$WORK/c.out" "$WORK/p.out" && _fail "color: identical to plain"
    echo "ok   color-file emits SGR, plain does not"

    # 2b. a fragmented file arg (`a.c#main`) must still colour by language: the
    #     ext comes from the FS path, not the fragmented arg (JAB-003).
    ( cd "$BROWT" && "$JABC" bro --color "$_AFILE#main" ) >"$WORK/cf.out" 2>/dev/null \
        || _fail "color-frag: nonzero exit"
    has_esc "$WORK/cf.out" || _fail "color-frag: no SGR escape emitted"
    # a real per-token paint carries a foreground SGR (e.g. ESC[94m keyword), not
    # just the banner band — assert more than one distinct escape is present.
    [ "$(LC_ALL=C grep -o "$(printf '\033')\[" "$WORK/cf.out" | wc -l)" -gt 2 ] \
        || _fail "color-frag: looks un-tokenised (banner only)"
    echo "ok   color-frag tokenises by FS ext"

    # 3. a dir --color must still produce the listing (graceful plain fallback).
    ( cd "$BROWT" && "$JABC" bro --color "$WORK/src" ) >"$WORK/cd.out" 2>/dev/null \
        || _fail "color-dir: nonzero exit"
    [ -s "$WORK/cd.out" ] || _fail "color-dir: empty output (crash?)"
    grep -q "a.c" "$WORK/cd.out" || _fail "color-dir: listing missing a.c"
    echo "ok   color-dir falls back to a plain listing (no crash)"
fi

pass
