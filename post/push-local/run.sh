#!/bin/sh
# test/post/push-local — POST-028: `jab post file:<path>?<branch>` pushes to a
# LOCAL store over the jab-to-jab wire (`jab receive-pack`, shared/serve.js).
# RULED 2026-07-16: a `file:`/authority-less-`be:` target runs the SERVER-SIDE
# process exactly like ssh; the `?query` is the BRANCH want and the PATH
# selects the project — a WORKTREE (GET-038 `.be`-file redirect) or a store
# shard.  Pre-fix the URI never reached the push arm: query-less fell into the
# Path/narrow slot ("no changes since base"), `?branch` into the LOCAL advance
# arm (a bogus local branch, peer unmoved).  Legs: FF push moves the peer
# trunk + a fresh clone sees it; at-tip re-push refuses; a behind cur refuses
# non-FF; both refusals leave the peer byte-identical; a self-push refuses
# loudly; `#msg` commit-then-push refuses (POST-027 ground, unimplemented);
# a bare `./path` arg STAYS the narrow slot; a worktree-path target lands in
# its BACKING store.  Native-free, no ssh/git — the serve/uploadpack shape.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)            # test/post/push-local
_ROOT=$(cd "$_CASE/../.." && pwd)               # repo root (test/)
JAB=${JABC:-${BIN:+$BIN/jab}}
JAB=${JAB:-$(command -v jab || true)}
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "SKIP [push-local] no $BEDIR/main.js" >&2; exit 0; }
[ -n "$JAB" ] && [ -x "$JAB" ] || { echo "SKIP [push-local] no jab (set BIN=)" >&2; exit 0; }

# The wire runs jab-to-jab: local exec spawns `jab upload-pack`/`receive-pack`.
export KEEPER_BIN="$JAB"
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"
WORK="$TMP/$$/post-push-local"
rm -rf "$WORK"; mkdir -p "$WORK"
# Plant the jsrc symlink above the scratch so bareword `jab` resolves THIS
# worktree's extension (the post.js/serve.js under test) via its upward scan.
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [push-local] $*" >&2; exit 1; }

# store tip of BRANCH ("" = trunk) in a store rooted at DIR, via the SAME
# store.js reader the serve uses (the slots-case idiom).
cat > "$WORK/.tip.js" <<'EOF'
const store=require(process.argv[3]+"/shared/store.js");
const k=store.open(process.argv[2],"");
const u=utf8.Encode((k.resolveRef(process.argv[4]||"")||"")+"\n");
const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
_tip() { "$JAB" "$WORK/.tip.js" "$1" "$BEDIR" "${2:-}" 2>/dev/null; }

# the wt's recorded cur tip (last #sha row in its wtlog).
_cur() { grep -aoE '#[0-9a-f]{40}' "$1/.be/wtlog" 2>/dev/null | tail -1 | tr -d '#'; }

# --- seed the PEER store (jab-native), publish trunk -----------------------
PEER="$WORK/peer"; mkdir -p "$PEER"; cd "$PEER"; mkdir .be
printf 'A\n' > a.txt
"$JAB" post 'c1' >/dev/null 2>&1 || _fail "peer seed post failed"
"$JAB" post '?'  >/dev/null 2>&1 || _fail "peer trunk publish failed"
C1=$(_tip "$PEER")
[ -n "$C1" ] || _fail "peer has no trunk tip after seeding"

# --- wtA: a wire clone (its OWN store), one commit ahead --------------------
WTA="$WORK/wta"; mkdir -p "$WTA"
( cd "$WTA" && "$JAB" get "be:$PEER/.be" ) >/dev/null 2>"$WORK/geta.err" \
    || { cat "$WORK/geta.err" >&2; _fail "wtA wire clone failed"; }
( cd "$WTA" && printf 'A\nB\n' > a.txt && "$JAB" put a.txt >/dev/null 2>&1 \
    && "$JAB" post '#c2' >/dev/null 2>&1 ) || _fail "wtA local c2 commit failed"
C2=$(_cur "$WTA")
[ -n "$C2" ] && [ "$C2" != "$C1" ] || _fail "wtA cur did not advance past c1"

# === FF push: file:<peer-shard>?main moves the peer trunk to cur ============
# Pre-fix this invocation NEVER reached the push arm (Query slot: a bogus
# LOCAL branch advance, rc=0, peer unmoved) — the peer-tip assert is the pin.
( cd "$WTA" && "$JAB" post "file:$PEER/.be?main" ) \
    >"$WORK/push.out" 2>"$WORK/push.err" \
    || { cat "$WORK/push.err" >&2; _fail "file: push failed"; }
[ "$(_tip "$PEER")" = "$C2" ] \
    || _fail "peer trunk did not FF to cur ($C2; got '$(_tip "$PEER")')"

# a FRESH clone off the peer sees the pushed tip + content.
FRESH="$WORK/fresh"; mkdir -p "$FRESH"
( cd "$FRESH" && "$JAB" get "be:$PEER/.be" ) >/dev/null 2>&1 \
    || _fail "fresh clone off the pushed peer failed"
[ "$(_cur "$FRESH")" = "$C2" ] || _fail "fresh clone is not at the pushed tip"
[ "$(cat "$FRESH/a.txt")" = "$(printf 'A\nB\n')" ] \
    || _fail "fresh clone content is not the pushed c2 tree"

# === at-tip re-push refuses; the peer stays byte-identical ==================
cp -a "$PEER" "$WORK/peer.attip"
if ( cd "$WTA" && "$JAB" post "file:$PEER/.be?main" ) \
     >"$WORK/attip.out" 2>"$WORK/attip.err"; then
    _fail "at-tip re-push unexpectedly succeeded: $(cat "$WORK/attip.out")"
fi
grep -q "already at cur's tip" "$WORK/attip.err" \
    || { cat "$WORK/attip.err" >&2; _fail "at-tip refusal is not the 'already at' report"; }
diff -r "$WORK/peer.attip" "$PEER" >/dev/null 2>&1 \
    || _fail "peer is not byte-identical after the at-tip refusal"

# === a self-push (target = own anchor store) refuses loudly =================
if ( cd "$WTA" && "$JAB" post "file:$WTA?main" ) >/dev/null 2>"$WORK/self.err"; then
    _fail "self-push unexpectedly succeeded"
fi
grep -q "own store" "$WORK/self.err" \
    || { cat "$WORK/self.err" >&2; _fail "self-push refusal does not name the own store"; }

# === a bare ./path arg STAYS the Path/narrow slot (never a push) ============
if ( cd "$WTA" && "$JAB" post './a.txt' ) >/dev/null 2>"$WORK/narrow.err"; then
    _fail "narrow './a.txt' post on a clean wt unexpectedly succeeded"
fi
grep -q "no changes since base" "$WORK/narrow.err" \
    || { cat "$WORK/narrow.err" >&2; _fail "bare ./path did not stay the narrow slot"; }

# === `#msg` commit-then-push refuses (POST-027 ground, not implemented) =====
if ( cd "$WTA" && "$JAB" post "file:$PEER/.be?main#zap" ) >/dev/null 2>"$WORK/frag.err"; then
    _fail "commit-then-push unexpectedly succeeded"
fi
grep -q "not supported" "$WORK/frag.err" \
    || { cat "$WORK/frag.err" >&2; _fail "#msg push refusal is not comprehensible"; }

# === wtB advances the peer past wtA, then wtA's push refuses non-FF =========
WTB="$WORK/wtb"; mkdir -p "$WTB"
( cd "$WTB" && "$JAB" get "be:$PEER/.be" ) >/dev/null 2>&1 \
    || _fail "wtB wire clone failed"
( cd "$WTB" && printf 'A\nB\nC\n' > a.txt && "$JAB" put a.txt >/dev/null 2>&1 \
    && "$JAB" post '#c3' >/dev/null 2>&1 ) || _fail "wtB local c3 commit failed"
C3=$(_cur "$WTB")
( cd "$WTB" && "$JAB" post "file:$PEER/.be?main" ) >/dev/null 2>"$WORK/push3.err" \
    || { cat "$WORK/push3.err" >&2; _fail "wtB FF push failed"; }
[ "$(_tip "$PEER")" = "$C3" ] || _fail "peer trunk did not FF to c3"

cp -a "$PEER" "$WORK/peer.nonff"
if ( cd "$WTA" && "$JAB" post "file:$PEER/.be?main" ) \
     >/dev/null 2>"$WORK/nonff.err"; then
    _fail "non-FF push unexpectedly succeeded"
fi
grep -q "can not be fast-forwarded" "$WORK/nonff.err" \
    || { cat "$WORK/nonff.err" >&2; _fail "non-FF refusal is not the FF report"; }
diff -r "$WORK/peer.nonff" "$PEER" >/dev/null 2>&1 \
    || _fail "peer is not byte-identical after the non-FF refusal"
# the authority-less `be:` scheme rides the SAME push arm (same refusal).
if ( cd "$WTA" && "$JAB" post "be:$PEER/.be?main" ) >/dev/null 2>"$WORK/benonff.err"; then
    _fail "be: non-FF push unexpectedly succeeded"
fi
grep -q "can not be fast-forwarded" "$WORK/benonff.err" \
    || { cat "$WORK/benonff.err" >&2; _fail "be: target did not reach the push arm"; }

# === a WORKTREE path target lands in its BACKING store (GET-038 redirect) ===
# A local `file:` get shares the peer's store (a `.be`-FILE secondary wt) —
# pushing at THAT wt's path must move the PEER store, creating ?feat at c3.
SEC="$WORK/sec"; mkdir -p "$SEC"
( cd "$SEC" && "$JAB" get "file://$PEER/.be#$C3" ) >/dev/null 2>&1 \
    || _fail "secondary (shared-store) wt clone failed"
[ -f "$SEC/.be" ] || _fail "fixture bug: sec/.be is not a redirect FILE"
( cd "$WTB" && "$JAB" post "file:$SEC?feat" ) >/dev/null 2>"$WORK/sec.err" \
    || { cat "$WORK/sec.err" >&2; _fail "push to a worktree path failed"; }
[ "$(_tip "$PEER" feat)" = "$C3" ] \
    || _fail "wt-path push did not land ?feat in the BACKING store ($C3; got '$(_tip "$PEER" feat)')"

echo "PASS [push-local]"
