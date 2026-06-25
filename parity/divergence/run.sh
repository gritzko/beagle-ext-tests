#!/bin/sh
# JSQUE-007 NEGATIVE proof: the golden-diff gate must FAIL on a 1-byte
# divergence — otherwise it is not a real gate.  We run the SAME put-multi
# scenario the put-multi case runs (so both real captures are byte-equal and
# would PASS), then inject a single-byte change into the JS-side capture and
# confirm assert_stdout exits non-zero.  Two injections are exercised:
#   (a) a content byte in a row uri  (catches a renderer divergence), and
#   (b) the normalised DATE column itself (catches a banner-column drift —
#       the [jobqueue] HUNK-parity blocker that substring checks miss).
# A passing parity oracle that ignored either would be a false green; this
# case turns that into a loud failure.  Run standalone (sources parity.sh).
. "$(dirname "$0")/../../lib/parity.sh"

seed_baseline 'printf "A\n" > a.txt; printf "B\n" > b.txt'
fork_pair
mutate 'sleep 0.02; printf "A2\n" > a.txt; printf "N\n" > n.txt'

# Capture both real outputs WITHOUT asserting (so we can sanity-check parity
# first, then deliberately break it).
( cd "$NAT" && run_native put a.txt n.txt ) >"$NAT.out" 2>"$NAT.err" || true
( cd "$JS"  && run_js     put a.txt n.txt ) >"$JS.out"  2>"$JS.err"  || true

# 0. sanity: the unmodified pair PASSES (assert_stdout returns cleanly).
assert_stdout "$NAT.out" "$JS.out" || _fail "baseline parity unexpectedly FAILED"
echo "ok: unmodified put parity passes (baseline)"

# expect_diff LABEL FILE — assert_stdout on (NAT, FILE) MUST fail; succeeding
# means the gate is blind to the injected byte.  assert_stdout calls _fail
# (exit 1) on divergence, so run it in a subshell and require non-zero.
expect_diff() {
    if ( assert_stdout "$NAT.out" "$2" ) >/dev/null 2>&1; then
        _fail "gate is BLIND: $1 was NOT caught"
    fi
    echo "ok: gate CAUGHT $1"
}

# (a) flip one byte in a row's path (a.txt -> a.txu) — a renderer/uri
# divergence in the rendered row text.
sed 's/a\.txt/a.txu/' "$JS.out" > "$JS.out.bytea"
cmp -s "$JS.out" "$JS.out.bytea" && _fail "byte-(a) injection produced no change"
expect_diff "a 1-byte row path divergence (a.txt->a.txu)" "$JS.out.bytea"

# (b) corrupt the DATE column so it no longer matches _norm's `H:MM` shape
# (`:36 ` -> `:3X `): native still normalises to `T `, the broken side keeps
# its raw column, so the two diverge AFTER _norm — proving the gate is
# full-line, not date-blind the way a substring check would be.  This is the
# class the [jobqueue] HUNK banner-column blocker lives in.
sed 's/\(:[0-9]\)[0-9]\( *put\)/\1X\2/' "$JS.out" > "$JS.out.byteb"
cmp -s "$JS.out" "$JS.out.byteb" && \
    sed -E 's/^( *[0-9]{1,2}:[0-9])[0-9]/\1X/' "$JS.out" > "$JS.out.byteb"
cmp -s "$JS.out" "$JS.out.byteb" && _fail "byte-(b) injection produced no change"
expect_diff "a date-column divergence (survives _norm)" "$JS.out.byteb"

pass
