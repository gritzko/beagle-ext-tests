#!/bin/sh
# test/mark/og — MARK-011: rendered pages carry Open Graph link-card meta.
#
# Both `mark` and `rss` must emit a heading-derived <title> + an OG block
# (og:title / og:description / og:type / og:url / og:image), and `rss` must
# fill the feed <description>.  The extractor is shared (render.pageMeta), so
# this drives the REAL verbs against a fixture project and asserts on the
# actual output files — the head, the absolute fragment-free og:image, and the
# feed item.  A second render with html/CNAME removed covers the no-base
# degradation (og:url/og:image dropped, title/og:title/og:description kept).
#
# DANGER (ticket): `jab mark`/`jab rss` write into `<project root>/html`, and
# projectRoot() climbs to the TOPMOST `.be` below $BE_ROOT — so every render
# here runs with BE_ROOT pinned ABOVE the fixture root, NEVER the live tree.
# Registered by the be/test glob as be-js-mark-og — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/mark/og
_ROOT=$(cd "$_CASE/../.." && pwd)                # test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "mark/og: cannot locate jab (set BIN=)" >&2; exit 2; }
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "mark/og: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/verbs/mark/render.js" ] || { echo "mark/og: SKIP — no render.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
WORK="$TMP/$$/mark/og"
rm -rf "$WORK"; mkdir -p "$WORK"
trap 'rc=$?; [ "$rc" = 0 ] && rm -rf "$TMP/$$"; exit $rc' EXIT

_fail() { echo "FAIL [mark/og] $*" >&2; exit 1; }
_has()  { grep -qF -- "$2" "$1" || _fail "$3 (want: $2)"; }
_hasnt(){ grep -qF -- "$2" "$1" && _fail "$3 (should NOT contain: $2)"; return 0; }

# ---- fixture project: own `.be` anchor, jsrc shard, html/ chrome, a post -----
SRC="$WORK/src"
mkdir -p "$SRC/.be" "$SRC/html" "$SRC/blog/img"
ln -sfn "$BEDIR" "$SRC/jsrc"
printf 'example.test\n' > "$SRC/html/CNAME"
printf '<link rel="stylesheet" href="/assets/css/style.css">\n' > "$SRC/html/head.html"
# The post: a `##` opener (the exact case the old H1-only metaOf missed), a
# reference-style FIRST image whose refdef carries a #fragment, then prose.
cat > "$SRC/blog/post.mkd" <<'EOF'
##  Hello OG World

![Darwin's sketch][1]
This is the intro paragraph with a [link][g] and *emphasis*.

A second paragraph that must NOT leak into the description.

[1]: ./img/darwin.jpg#rightw30
[g]: ./git.mkd
EOF
: > "$SRC/blog/img/darwin.jpg"

# BE_ROOT sits ABOVE the fixture root so the `.be` climb stops AT $SRC — the
# render can never escape to the live journal tree.
export BE_ROOT="$WORK"
cd "$SRC"

# ---- (1) rss: page head + feed item ------------------------------------------
"$JABC" rss blog/post.mkd >"$WORK/rss.out" 2>"$WORK/rss.err" \
    || { cat "$WORK/rss.err" >&2; _fail "jab rss failed"; }
PAGE="$SRC/html/blog/post.html"
[ -f "$PAGE" ] || _fail "rss did not write html/blog/post.html"

_has  "$PAGE" '<title>Hello OG World</title>'                    "heading is the <title>"
_has  "$PAGE" '<meta property="og:title" content="Hello OG World">' "og:title = heading"
_has  "$PAGE" '<meta property="og:type" content="article">'      "og:type = article"
_has  "$PAGE" '<meta property="og:url" content="https://example.test/blog/post.html">' "og:url absolute"
_has  "$PAGE" '<meta property="og:image" content="https://example.test/blog/img/darwin.jpg">' "og:image absolute + fragment-free"
# the #fragment stays in the BODY <img> (layout), but must be gone from og:image.
grep 'property="og:image"' "$PAGE" | grep -q '#' && _fail "og:image still carries the #fragment"
grep -q '<meta property="og:description" content="This is the intro paragraph' "$PAGE" \
    || _fail "og:description is the intro text"
# only the FIRST paragraph is the description — the second must not leak into it.
grep 'property="og:description"' "$PAGE" | grep -qi 'second paragraph' \
    && _fail "og:description leaked the second paragraph"

FEED="$SRC/html/feed.rss"
[ -f "$FEED" ] || _fail "rss did not write html/feed.rss"
_has "$FEED" '<title>Hello OG World</title>'                     "feed item title = heading"
# feed <description> must be NON-EMPTY (the old bug: empty for ## posts).
grep -q '<description>This is the intro paragraph' "$FEED" \
    || _fail "feed <description> is empty / not the intro"

# ---- (2) mark renders the same head ------------------------------------------
rm -f "$PAGE"
"$JABC" mark blog/post.mkd >"$WORK/mark.out" 2>"$WORK/mark.err" \
    || { cat "$WORK/mark.err" >&2; _fail "jab mark failed"; }
[ -f "$PAGE" ] || _fail "mark did not write html/blog/post.html"
_has "$PAGE" '<title>Hello OG World</title>'                     "mark: heading <title>"
_has "$PAGE" '<meta property="og:image" content="https://example.test/blog/img/darwin.jpg">' "mark: og:image absolute"

# ---- (3) no-CNAME degradation: title/description stay, og:url/og:image drop ---
rm -f "$SRC/html/CNAME" "$PAGE"
"$JABC" mark blog/post.mkd >"$WORK/nocname.out" 2>"$WORK/nocname.err" \
    || { cat "$WORK/nocname.err" >&2; _fail "jab mark (no CNAME) failed"; }
[ -f "$PAGE" ] || _fail "mark (no CNAME) did not write the page"
_has   "$PAGE" '<title>Hello OG World</title>'                   "no-CNAME: <title> kept"
_has   "$PAGE" '<meta property="og:title" content="Hello OG World">' "no-CNAME: og:title kept"
grep -q '<meta property="og:description" content="This is the intro paragraph' "$PAGE" \
    || _fail "no-CNAME: og:description kept"
_hasnt "$PAGE" 'og:url'                                          "no-CNAME: og:url dropped"
_hasnt "$PAGE" 'og:image'                                        "no-CNAME: og:image dropped"

echo "PASS [mark/og]"
