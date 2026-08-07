#!/bin/sh
# test/mark/meta — MARK-015: the head meta block is a run of key-value ROWS.
#
# A `Key: value` line ([/wiki/StrictMark] "Meta pairs") is a LEAF BLOCK, so it
# must never be joined into a paragraph: today `classify` has no meta marker and
# the whole indented head of every ticket lands in ONE `<p>` ("Now: OPEN Sev:
# HIGH Ask: …").  This drives the REAL `jab mark` over a fixture ticket and
# asserts (a) one addressable row per pair, (b) the ticket-code keys
# (See:/Sub:/Dup:/On1:/On2:) link to the ticket page — thin `TOPIC/KEY.mkd` and
# fat `TOPIC/KEY/README.mkd` — (c) every other value stays VERBATIM (no inline
# layer inside a pair), and (d) the `Due\:` escape stays prose.
#
# DANGER (as test/mark/og): `jab mark` writes into `<project root>/html` and
# projectRoot() climbs to the TOPMOST `.be` below $BE_ROOT — BE_ROOT is pinned
# ABOVE the fixture root here, so no render can reach the live tree.
# Registered by the be/test glob as be-js-mark-meta — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/mark/meta
_ROOT=$(cd "$_CASE/../.." && pwd)                # test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "mark/meta: cannot locate jab (set BIN=)" >&2; exit 2; }
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "mark/meta: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/verbs/mark/render.js" ] || { echo "mark/meta: SKIP — no render.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
WORK="$TMP/$$/mark/meta"
rm -rf "$WORK"; mkdir -p "$WORK"
trap 'rc=$?; [ "$rc" = 0 ] && rm -rf "$TMP/$$"; exit $rc' EXIT

_fail() { echo "FAIL [mark/meta] $*" >&2; exit 1; }
_has()  { grep -qF -- "$2" "$1" || _fail "$3 (want: $2)"; }
_hasnt(){ grep -qF -- "$2" "$1" && _fail "$3 (should NOT contain: $2)"; return 0; }

# ---- fixture project: own `.be` anchor, jsrc shard, a thin + a fat ticket ----
SRC="$WORK/src"
mkdir -p "$SRC/.be" "$SRC/html" "$SRC/todo/DEMO/DEMO-003"
ln -sfn "$BEDIR" "$SRC/jsrc"

# the link TARGETS: DEMO-002 thin, DEMO-003 fat (README.mkd).
printf '#   DEMO-002: the thin target\n' > "$SRC/todo/DEMO/DEMO-002.mkd"
printf '#   DEMO-003: the fat target\n'  > "$SRC/todo/DEMO/DEMO-003/README.mkd"

# the page under test: a head meta block indented four spaces, as every ticket
# writes it.  `Rev:` is a URI (must stay text), `Due\:` is the escape.
cat > "$SRC/todo/DEMO/DEMO-001.mkd" <<'EOF'
#   DEMO-001: the meta block renders as rows

    Now: OPEN
    Sev: HIGH
    Ask: gritzko
    Rev: ///be#4b64468c
    See: DEMO-002
    Sub: DEMO-003
    Due\: 2026-08-07

Body prose that stays a paragraph.
EOF

export BE_ROOT="$WORK"
cd "$SRC"

"$JABC" mark todo/DEMO/DEMO-001.mkd >"$WORK/mark.out" 2>"$WORK/mark.err" \
    || { cat "$WORK/mark.err" >&2; _fail "jab mark failed"; }
PAGE="$SRC/html/todo/DEMO/DEMO-001.html"
[ -f "$PAGE" ] || _fail "mark did not write html/todo/DEMO/DEMO-001.html"

# ---- (1) the pairs are NOT one paragraph -------------------------------------
grep -q 'Now: OPEN Sev: HIGH' "$PAGE" && _fail "the meta pairs are glued into one line"
grep -q '<p>' "$PAGE" && grep -A1 '<p>' "$PAGE" | grep -q 'Now: OPEN' \
    && _fail "a meta pair reached the paragraph layer"

# ---- (2) one addressable row per pair ----------------------------------------
_has "$PAGE" '<dl class="meta"><dt>Now:</dt><dd>OPEN</dd></dl>'      "Now: row"
_has "$PAGE" '<dl class="meta"><dt>Sev:</dt><dd>HIGH</dd></dl>'      "Sev: row"
_has "$PAGE" '<dl class="meta"><dt>Ask:</dt><dd>gritzko</dd></dl>'   "Ask: row"
ROWS=$(grep -c '<dl class="meta">' "$PAGE" || true)
[ "$ROWS" = "6" ] || _fail "want 6 meta rows, got $ROWS"

# ---- (3) ticket-code values are links (thin + fat) ---------------------------
_has "$PAGE" '<dt>See:</dt><dd><a href="/todo/DEMO/DEMO-002.html">DEMO-002</a></dd>' \
     "See: links the thin ticket"
_has "$PAGE" '<dt>Sub:</dt><dd><a href="/todo/DEMO/DEMO-003/README.html">DEMO-003</a></dd>' \
     "Sub: links the fat ticket"

# ---- (4) a non-ticket value is VERBATIM: no link, no inline layer ------------
_has   "$PAGE" '<dt>Rev:</dt><dd>///be#4b64468c</dd>'                "Rev: value verbatim"
grep '<dt>Rev:' "$PAGE" | grep -q '<a ' && _fail "Rev: value was linked"

# ---- (5) the `Due\:` escape is prose, not a pair -----------------------------
grep -q '<dt>Due:' "$PAGE" && _fail "the escaped 'Due\\:' became a meta pair"
_has "$PAGE" 'Body prose that stays a paragraph.'                    "body prose still renders"

echo "PASS [mark/meta]"
