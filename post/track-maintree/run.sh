#!/bin/sh
# test/post/track-maintree — POST-030: bare `jab post` from a worktree whose
# wtlog TRACK row is the empty-authority `///be/` (maintree-relative worktree)
# form must FF the target maintree's base to cur's tip.  The live 2026-07-17
# defect: the WT carried a mounted submodule S whose OWN track row is the
# self-referential `//WT/S` (submount) with a DIVERGENT store trunk; the bare
# post fanned into that clean sub, which fell through advanceTrack →
# advanceBranch on the sub's own trunk and threw `` `?` can not be
# fast-forwarded `` (post.js advanceBranch, empty target).  That throw is not a
# NONE refusal, so postSubs re-threw it and the parent's (FF-able) maintree
# advance never ran.  RED on the pre-fix code with that exact exception.
#
# Ruling (gritzko 2026-07-17): a bare-track advance is a PURE FF — a clean
# target gets cur checked out clean; a DIRTY target REFUSES rather than weaves.
# Spec: /wiki/POST.mkd §"Summary of invocation patterns" item 1 (bare post
# advances the TRACK; a worktree track FFs the target's base).
#
# Fixture: SRC project root; SRC/be is the maintree (resolves as ///be/); a
# clone under SRC/work/WT tracks ///be/ and mounts a self-ref sub S with a
# divergent trunk.  This needs the //NAME / /// nav addressing (rs_work_root),
# so the case builds its own SRC/work fixture (the test/post/wt-target pattern).
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/post/track-maintree
_ROOT=$(cd "$_CASE/../.." && pwd)                # repo root (test/)
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "post/track-maintree: cannot locate jab (set BIN=)" >&2; exit 2; }
_BIN=$(dirname "$JABC")
BE=$JABC
BEDIR="${BEDIR:-$_ROOT/..}"
[ -f "$BEDIR/main.js" ] || { echo "post/track-maintree: SKIP — no $BEDIR/main.js yet" >&2; exit 0; }

case ":$PATH:" in *":$_BIN:"*) ;; *) PATH="$_BIN:$PATH"; export PATH ;; esac
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=track-maintree
WORK="$TMP/$$/post/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [post/$NAME] $*" >&2; exit 1; }
pass() { echo "PASS [post/$NAME]"; }

. "$_ROOT/lib/repo-setup.sh"

# URI-016: SRC is the PROJECT ROOT (its own `.be/` anchor); `SRC/work/NAME` IS
# `//NAME` and `///be/` IS `SRC/be`.  BE_ROOT confines the climb above SRC.
SRC="$WORK/src"
WORKD=$(rs_work_root "$SRC")
# jsrc verb-resolution shim above EVERY scratch tree (the substore sits beside
# SRC, so plant at $WORK too, not only under SRC).
ln -sfn "$BEDIR" "$WORK/jsrc"
ln -sfn "$BEDIR" "$SRC/jsrc"
export BE_ROOT="$WORK"

# --- JS seeding/probe helpers (the tricky wtlog/ref shapes) -----------------
_base() {   # _base DIR — the worktree's OWN cur row (wtlog curTip) sha
    cat > "$WORK/.base.js" <<'EOF'
const be=require(process.argv[3]+"/core/discover.js");
const wtlog=require(process.argv[3]+"/shared/wtlog.js");
const c=wtlog.open(be.treeAt(process.argv[2])).curTip();
const u=utf8.Encode(((c&&c.sha)||"")+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);
EOF
    "$JABC" "$WORK/.base.js" "$1" "$BEDIR" 2>/dev/null
}
_settrunk() {   # _settrunk DIR SHA — seed the store's trunk ref (divergent seed)
    cat > "$WORK/.tr.js" <<'EOF'
const be=require(process.argv[2]+"/core/discover.js");const store=require(process.argv[2]+"/shared/store.js");
const info=be.treeAt(process.argv[3]);const k=store.open(info.storePath,info.project);
store.set(k.shard,"",process.argv[4]);
EOF
    "$JABC" "$WORK/.tr.js" "$BEDIR" "$1" "$2"
}
_resetcur() {   # _resetcur DIR SHA — append a get pin row (cur ← SHA)
    cat > "$WORK/.rc.js" <<'EOF'
const ulog=require(process.argv[2]+"/shared/ulog.js");const be=require(process.argv[2]+"/core/discover.js");
const info=be.treeAt(process.argv[3]);
ulog.append(info.bePath,[{verb:"get",uri:URI.make(undefined,undefined,undefined,"",process.argv[4])}]);
EOF
    "$JABC" "$WORK/.rc.js" "$BEDIR" "$1" "$2"
}
_seedtrack() {  # _seedtrack DIR AUTH PATH SHA — append `get //AUTH/PATH#SHA`
    cat > "$WORK/.st.js" <<'EOF'
const ulog=require(process.argv[2]+"/shared/ulog.js");const be=require(process.argv[2]+"/core/discover.js");
const info=be.treeAt(process.argv[3]);
ulog.append(info.bePath,[{verb:"get",uri:URI.make(undefined,process.argv[4],process.argv[5],undefined,process.argv[6])}]);
EOF
    "$JABC" "$WORK/.st.js" "$BEDIR" "$1" "$2" "$3" "$4"
}
_pinrow() {     # _pinrow WTLOGPATH SUBPATH SHA — seed a gitlink `put SUBPATH#SHA`
    cat > "$WORK/.pr.js" <<'EOF'
const ulog=require(process.argv[2]+"/shared/ulog.js");
ulog.append(process.argv[3],[{verb:"put",uri:URI.make(undefined,undefined,process.argv[4],undefined,process.argv[5])}]);
EOF
    "$JABC" "$WORK/.pr.js" "$BEDIR" "$1" "$2" "$3"
}

# --- SUBSTORE: a sub with a trunk DIVERGENT from its cur (the live shape) ----
# c1 → c2, trunk pinned at c2, cur reset to c1, then c3 off c1: c2 and c3 are
# siblings, so isAncestor(trunk c2, cur c3) is false → advanceBranch non-FF.
SUBSTORE="$WORK/substore"; mkdir -p "$SUBSTORE/.be"
( cd "$SUBSTORE" && printf 'v1\n' > s.txt && "$BE" post '#s1' ) >/dev/null 2>&1 || _fail "sub s1"
S_C1=$(_base "$SUBSTORE")
( cd "$SUBSTORE" && printf 'v2\n' > s.txt && "$BE" put s.txt && "$BE" post '#s2' ) >/dev/null 2>&1 || _fail "sub s2"
S_C2=$(_base "$SUBSTORE")
_settrunk "$SUBSTORE" "$S_C2"
_resetcur "$SUBSTORE" "$S_C1"
( cd "$SUBSTORE" && printf 'v3\n' > s.txt && "$BE" put s.txt && "$BE" post '#s3' ) >/dev/null 2>&1 || _fail "sub s3"
S_C3=$(_base "$SUBSTORE")
[ "$S_C3" != "$S_C2" ] || _fail "fixture: sub cur == trunk (not divergent)"

# --- maintree SRC/be: the ///be/ TARGET, commit c1 -------------------------
mkdir -p "$SRC/be/.be"
( cd "$SRC/be" && printf 'A\n' > a.txt && "$BE" post '#c1' ) >/dev/null 2>&1 || _fail "be c1"
BE_TIP0=$(_base "$SRC/be")

# --- clone WT under work/, sharing be's store, re-anchor track to ///be/ -----
mkdir -p "$WORKD/WT"
( cd "$WORKD/WT" && "$BE" get "file://$SRC/be/.be#$BE_TIP0" ) >/dev/null 2>&1 || _fail "WT clone"
( cd "$WORKD/WT" && "$BE" get "///be/#$BE_TIP0" ) >/dev/null 2>&1 || _fail "WT get ///be/"
# byte-match the live TRACK shape: an empty-authority `get ///be/#<sha>` row.
grep -qE '	get	///be/#[0-9a-f]{40}' "$WORKD/WT/.be" \
    || _fail "fixture: WT track row is not the ///be/ form: $(cat "$WORKD/WT/.be")"

# --- mount the self-ref sub S in WT and commit c2 (folds the gitlink) -------
( cd "$WORKD/WT"
  cat > .gitmodules <<EOF
[submodule "S"]
	path = S
	url = file://$SUBSTORE/.be?/
EOF
  mkdir -p S
  _r=$(head -c 9 .be)
  printf '%s\tget\tfile:%s/.be/?/#%s\n' "$_r" "$SUBSTORE" "$S_C3" > S/.be
  printf 'v3\n' > S/s.txt
  "$BE" put .gitmodules ) >/dev/null 2>&1 || _fail "mount sub (put)"
_pinrow "$WORKD/WT/.be" "S" "$S_C3"
( cd "$WORKD/WT" && printf 'A2\n' > a.txt && "$BE" put a.txt && "$BE" post '#c2' ) >/dev/null 2>&1 || _fail "WT c2"
WT_TIP=$(_base "$WORKD/WT")
[ "$WT_TIP" != "$BE_TIP0" ] || _fail "fixture: WT did not advance past be"
# the sub's OWN track is the self-ref //WT/S, its store trunk stays divergent.
_seedtrack "$WORKD/WT/S" "//WT" "/S" "$S_C3"
_settrunk "$WORKD/WT/S" "$S_C2"
grep -qE '	get	//WT/S#[0-9a-f]{40}' "$WORKD/WT/S/.be" \
    || _fail "fixture: sub track is not the //WT/S form"

# ===== leg 1: bare post FFs the ///be/ maintree; NO `?` refusal =============
RC=0
( cd "$WORKD/WT" && "$BE" post ) >"$WORK/p1.out" 2>"$WORK/p1.err" || RC=$?
if grep -q '`?` can not be fast-forwarded' "$WORK/p1.err"; then
    echo "  stderr: $(cat "$WORK/p1.err")" >&2
    _fail "bare post threw the \`?\` non-FF refusal (the POST-030 sub fan-out bug)"
fi
[ "$RC" = 0 ] || { echo "  stderr: $(cat "$WORK/p1.err")" >&2; _fail "bare post failed rc=$RC"; }
[ "$(_base "$SRC/be")" = "$WT_TIP" ] \
    || _fail "maintree base did not FF to cur's tip (got $(_base "$SRC/be") want $WT_TIP)"
[ "$(cat "$SRC/be/a.txt")" = "A2" ] \
    || _fail "maintree files not updated (a.txt='$(cat "$SRC/be/a.txt")' want 'A2')"
# the clean sub was NOT bare-advanced as a side effect (2 rows, cur untouched).
[ "$(_base "$WORKD/WT/S")" = "$S_C3" ] || _fail "sub S cur moved (side effect)"

# ===== leg 2: a second bare post is a clean no-op (already at) ==============
RC=0
( cd "$WORKD/WT" && "$BE" post ) >"$WORK/p2.out" 2>"$WORK/p2.err" || RC=$?
grep -q '`?` can not be fast-forwarded' "$WORK/p2.err" && _fail "second post threw \`?\` refusal"
grep -q "already at cur's tip" "$WORK/p2.err" \
    || { cat "$WORK/p2.err" >&2; _fail "second bare post did not refuse 'already at cur's tip'"; }
[ "$(_base "$SRC/be")" = "$WT_TIP" ] || _fail "second post moved the maintree base"

# ===== leg 3: a DIRTY target REFUSES (just-ff ruling — no weave) ============
# WT commits c3 (ahead again); dirty the maintree; bare post must refuse and
# leave the maintree base + its dirty file untouched.
( cd "$WORKD/WT" && printf 'A3\n' > a.txt && "$BE" put a.txt && "$BE" post '#c3' ) >/dev/null 2>&1 || _fail "WT c3"
WT_TIP3=$(_base "$WORKD/WT")
[ "$WT_TIP3" != "$WT_TIP" ] || _fail "fixture: WT c3 did not advance"
BE_BASE_PRE=$(_base "$SRC/be")
printf 'DIRTY\n' > "$SRC/be/a.txt"          # uncommitted change in the target
RC=0
( cd "$WORKD/WT" && "$BE" post ) >"$WORK/p3.out" 2>"$WORK/p3.err" || RC=$?
[ "$RC" -ne 0 ] || { echo "  stdout: $(cat "$WORK/p3.out")" >&2; _fail "bare post onto a DIRTY target SUCCEEDED (must refuse)"; }
grep -q "uncommitted changes" "$WORK/p3.err" \
    || { cat "$WORK/p3.err" >&2; _fail "dirty-target refusal does not say 'uncommitted changes'"; }
[ "$(_base "$SRC/be")" = "$BE_BASE_PRE" ] || _fail "dirty-target post moved the maintree base"
[ "$(cat "$SRC/be/a.txt")" = "DIRTY" ] || _fail "dirty-target post touched the target's file"

pass
