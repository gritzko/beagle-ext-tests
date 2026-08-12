#!/bin/sh
# test/post/wt-target-root — POST-038: `post ///X/` (the canonical MAIN-TREE
# sub address, authority `//` + EMPTY host) must route to the wt-target leg
# exactly like `post //X`, i.e. FF-advance X's OWN base to cur's tip
# (/wiki/POST.mkd row 4).  parseSlots gated that leg on `u.host` being
# truthy, so `///X/` fell through to the narrow PATH slot (narrow = "/X/"),
# post took the COMMITTING leg, and a clean wt died on "no changes since
# base" — an error describing an operation nobody asked for.  On a DIRTY wt
# with a `#msg` the same spell would have narrow-COMMITTED at the bogus path.
#
# RED before the fix: `post ///be/` -> "no changes since base", the target's
# base unmoved.  GREEN after: the target's base is cur's tip, cur untouched,
# and the re-run refuses in plain words ("already at cur's tip") instead of
# ever reaching the committing leg.
#
# Fixture: SRC is the project root, so `///be` IS `SRC/be` ([/wiki/URI] step 2,
# discover.wtdir's empty-host arm) and `SRC/work/A` is `//A`.  A is a clone of
# `///be` that committed one past it.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/wt-target-root
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/wt-target-root: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/wt-target-root: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=wt-target-root
WORK="$TMP/$$/post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [post/$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [post/$NAME]"; }

. "$_ROOT/lib/repo-setup.sh"

# URI-016: SRC is the PROJECT ROOT; `SRC/work/NAME` IS `//NAME` and a plain
# child `SRC/be` IS `///be` (test/post/wt-target-sub pattern).
SRC="$WORK/src"
WORKD=$(rs_work_root "$SRC")
ln -sfn "$BEDIR" "$SRC/jsrc"
export BE_ROOT="$WORK"

# base helper: the worktree's OWN cur row (wtlog.js curTip) — what an advance
# must move, and what resolve_hash step 5.5 reads (test/post/wt-target's probe).
_base() {   # _base DIR
    cat > "$WORK/.base.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const info=be.treeAt(process.argv[2]);
const c=wtlog.open(info).curTip();
const u=utf8.Encode(((c&&c.sha)||"")+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.base.js" "$1" "$BEDIR" 2>/dev/null
}

# --- `///be`: a main-tree sub at the project root, commit b1 ----------------
mkdir -p "$SRC/be/.be"
( cd "$SRC/be" && printf 'v1\n' > f.txt && "$BE" post '#b1' ) >/dev/null 2>&1 \
    || _fail "///be bootstrap post failed"
B0=$(_base "$SRC/be")
[ -n "$B0" ] || _fail "fixture: ///be has no cur tip"

# --- //A: a clone of ///be, then ONE commit ahead ---------------------------
mkdir -p "$WORKD/A"
( cd "$WORKD/A" && "$JABC" get "file://$SRC/be/.be#$B0" ) >/dev/null 2>&1 \
    || _fail "A clone failed"
( cd "$WORKD/A" && printf 'v2\n' > f.txt && "$JABC" put f.txt && "$JABC" post '#a2' ) \
    >/dev/null 2>&1 || _fail "A a2 post failed"
A1=$(_base "$WORKD/A")
[ -n "$A1" ] && [ "$A1" != "$B0" ] || _fail "fixture: A did not advance past ///be"

# --- the op under test: `post ///be/` FF-advances the main-tree sub ---------
RC=0
( cd "$WORKD/A" && "$JABC" post '///be/' ) >"$WORK/adv.out" 2>"$WORK/adv.err" || RC=$?
SUB_BASE=$(_base "$SRC/be")

if [ "$RC" -ne 0 ] || [ "$SUB_BASE" != "$A1" ]; then
    echo "post/wt-target-root: RED (rc=$RC) — 'post ///be/' did not FF the target" >&2
    echo "  stdout: $(cat "$WORK/adv.out")" >&2
    echo "  stderr: $(cat "$WORK/adv.err")" >&2
    echo "  ///be base before=$B0 after=$SUB_BASE want=$A1" >&2
    _fail "post ///be/ did not advance the target's base (POST-038)"
fi
grep -q 'no changes since base' "$WORK/adv.err" "$WORK/adv.out" 2>/dev/null \
    && _fail "post ///be/ still took the COMMITTING leg (narrow misparse)"
[ "$(cat "$SRC/be/f.txt")" = "v2" ] \
    || _fail "the advance did not materialise cur's files into ///be"
[ "$(_base "$WORKD/A")" = "$A1" ] \
    || _fail "post ///be/ moved cur's OWN base (it must commit nothing)"

# --- a CLEAN, already-equal target refuses in PLAIN WORDS, never committing --
RC=0
( cd "$WORKD/A" && "$JABC" post '///be/' ) >"$WORK/eq.out" 2>"$WORK/eq.err" || RC=$?
[ "$RC" != 0 ] || _fail "post ///be/ over an already-equal target did NOT refuse"
grep -q "already at cur's tip" "$WORK/eq.err" "$WORK/eq.out" 2>/dev/null \
    || { cat "$WORK/eq.err" >&2; _fail "not the plain-words 'already at cur's tip' refusal"; }
grep -q 'no changes since base' "$WORK/eq.err" "$WORK/eq.out" 2>/dev/null \
    && _fail "the clean-wt case still reaches the committing leg"

# --- ahead again + DIRTY: the advance still runs, cur commits nothing -------
( cd "$WORKD/A" && printf 'v3\n' > f.txt && "$JABC" put f.txt && "$JABC" post '#a3' ) \
    >/dev/null 2>&1 || _fail "A a3 post failed"
A2=$(_base "$WORKD/A")
( cd "$WORKD/A" && printf 'dirty\n' > d.txt && "$JABC" put d.txt ) >/dev/null 2>&1 \
    || _fail "could not dirty A"
RC=0
( cd "$WORKD/A" && "$JABC" post '///be/' ) >"$WORK/dirty.out" 2>"$WORK/dirty.err" || RC=$?
[ "$RC" = 0 ] || { cat "$WORK/dirty.err" >&2; _fail "dirty 'post ///be/' failed (rc=$RC)"; }
[ "$(_base "$SRC/be")" = "$A2" ] || _fail "dirty post ///be/ did not FF the target to $A2"
[ "$(_base "$WORKD/A")" = "$A2" ] \
    || _fail "post ///be/ COMMITTED in cur (the narrow-commit wrong-op)"

# --- the WRONG-OP shape: `///be/#msg` (one arg, so it reaches post as an
# OPERAND) must not resolve `#msg` as a hash nor narrow-commit at `/be/` ------
RC=0
( cd "$WORKD/A" && "$JABC" post '///be/#msg' ) >"$WORK/frag.out" 2>"$WORK/frag.err" || RC=$?
[ "$RC" != 0 ] || _fail "post ///be/#msg did NOT refuse"
grep -q 'is not supported' "$WORK/frag.err" "$WORK/frag.out" 2>/dev/null \
    || { cat "$WORK/frag.err" >&2; _fail "///be/#msg is not the plain-words `#` refusal"; }
grep -qE 'HASHNONE|no changes since base' "$WORK/frag.err" "$WORK/frag.out" 2>/dev/null \
    && _fail "///be/#msg still hits the hash resolver / committing leg"
[ "$(_base "$WORKD/A")" = "$A2" ] || _fail "post ///be/#msg committed in cur"

# --- slot ROUTING, straight off parseSlots (post._parseSlots) ---------------
# `///X[/sub]` and `//X` alike land in the wt slot and NEVER in `narrow`; a
# bare `//`/`///` (authority, but no tree named) refuses in plain words.
# (loop.js context-promotes a bare `//`/`///` before post sees it, so that
# guard has no CLI spelling — probe the routing directly.)
cat > "$WORK/.slots.js" <<'EOF'
const post = require(process.argv[2] + "/verbs/post/post.js");
let out = "";
for (const a of ["//X", "//X/sub", "///be/", "///be", "///be/sub/", "//", "///"]) {
  let s; try { s = post._parseSlots([a]); }
  catch (e) { out += a + " THROW " + e + "\n"; continue; }
  out += a + " wt=" + (s.wt ? s.wtUri : "-") + " narrow=" + (s.narrow || "-") +
         " host=" + (s.host ? "y" : "-") + "\n";
}
const b = utf8.Encode(out); const buf = io.buf(b.length + 8); buf.feed(b); io.write(1, buf);
EOF
"$JABC" "$WORK/.slots.js" "$BEDIR" > "$WORK/slots.out" 2>&1 \
    || { cat "$WORK/slots.out" >&2; _fail "parseSlots probe failed"; }
for U in "//X" "//X/sub" "///be/" "///be" "///be/sub/"; do
    grep -q "^$U wt=$U narrow=- host=-\$" "$WORK/slots.out" \
        || { cat "$WORK/slots.out" >&2; _fail "\`$U\` does not route to the wt slot"; }
done
grep -q '^// THROW .*names no worktree' "$WORK/slots.out" \
    || { cat "$WORK/slots.out" >&2; _fail "bare \`//\` does not refuse in plain words"; }
grep -q '^/// THROW .*names no worktree' "$WORK/slots.out" \
    || { cat "$WORK/slots.out" >&2; _fail "bare \`///\` does not refuse in plain words"; }

pass
