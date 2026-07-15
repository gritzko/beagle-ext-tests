#!/bin/sh
# test/bro/vim — BE-047 `vim`/`nvim` editor verbs.  Three legs, all headless:
#   (1) CLI: `jab vim <file>` runs the VERB-NAMED editor (a fake PATH `vim`/
#       `nvim` script recording its argv + appending a marker) on the RESOLVED
#       path (context-dir aware; NAVESCAPE `..` climb refused; bare = VIMNONE).
#   (2) pager edge (in-process, the pty.js model): a typed `:vim` must cook the
#       tty BEFORE driving the editor spell (context threaded), re-enter raw
#       AFTER, then RE-DRIVE the view's own spell so the edit shows.
#   (3) full stack (python pty.fork, the universal model), three modes: BE-048
#       launch (`jab cat f` + bare :vim/:diff/:why target f), BE-047 nav
#       (:spell-nav'd file + :vim), BE-048 guard (`jab status //wt` gains NO
#       phantom path — :vim errs on the dir, :diff stays tree-wide).
# Registered by the be/test glob as be-js-bro-vim — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/bro/vim
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "bro/vim: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "bro/vim: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/verbs/vim/vim.js" ] || { echo "bro/vim: SKIP — no verbs/vim (pre-BE-047)" >&2; exit 0; }
[ -f "$BEDIR/views/bro/pager.js" ] || { echo "bro/vim: SKIP — no pager.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

: "${TMP:=/tmp}"; export TMP
NAME=vim
WORK="$TMP/$$/bro/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
export WORK
# Hermetic firewall + the jsrc shard symlink so bareword `jab vim` resolves the
# extension via jab's upward jsrc/-scan from the worktree cwd.
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
# PUT-006: rm the pid scratch on clean exit (0); keep it on failure for debug.
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [bro/$NAME] $*" >&2; exit 1; }

# tty-binding probe (leg 2/3 need openpty); SKIP cleanly on a pre-JS-053 jab.
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.raw === "function" &&
           typeof tty.openpty === "function" && typeof io.spawnFds === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo no)
[ "$HAS" = "yes" ] || { echo "bro/vim: SKIP — jab lacks tty/spawnFds (got '$HAS')" >&2; exit 0; }

# The FAKE editors: record the argv path, append a marker line, exit 0.  The
# verb spawns the binary NAMED BY THE VERB via execvp, so PATH selects these.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/vim" <<EOF
#!/bin/sh
echo "\$1" >> "$WORK/vim.args"
echo "EDITED-BY-VIM" >> "\$1"
EOF
cat > "$WORK/bin/nvim" <<EOF
#!/bin/sh
echo "\$1" >> "$WORK/nvim.args"
echo "EDITED-BY-NVIM" >> "\$1"
EOF
chmod +x "$WORK/bin/vim" "$WORK/bin/nvim"
PATH="$WORK/bin:$PATH"; export PATH

# The scratch worktree lives under `work/` (`<project root>/work/wt`, the BE-031
# work/ layout) so navCwd names it //wt — the BE-048 authority-only guard leg
# needs the name.  URI-016: the project root is DETECTED by the `.be` climb, not
# declared by an env var, so $WORK must ANCHOR one (rs_work_root).
. "$_ROOT/lib/repo-setup.sh"
WORKD=$(rs_work_root "$WORK")
WT="$WORKD/wt"; mkdir -p "$WT/.be" "$WT/sub"
cd "$WT"
printf 'ORIGINAL\n'  > doc.txt
printf 'OTHERFILE\n' > other.txt
printf 'alpha\n'     > sub/a.txt
"$BE" post 'bro/vim seed' >/dev/null 2>&1 || _fail "seed post failed"
echo 'OTHER-CHANGED' >> other.txt   # a 2nd dirty file: tree- vs file-scoped diff

# --- leg 1: the plain-CLI verb ---------------------------------------------
# (a) `jab vim sub/a.txt` from the wt root: the fake vim ran on the RESOLVED
#     absolute path and its edit landed.
( cd "$WT" && "$JABC" vim sub/a.txt ) >"$WORK/v1.out" 2>&1 \
    || _fail "(a) jab vim sub/a.txt exited non-zero: $(cat "$WORK/v1.out")"
grep -q 'EDITED-BY-VIM' "$WT/sub/a.txt" || _fail "(a) fake vim did not edit sub/a.txt"
grep -qx "$WT/sub/a.txt" "$WORK/vim.args" \
    || _fail "(a) vim ran on the wrong path: $(cat "$WORK/vim.args" 2>/dev/null)"
echo "ok   (a) CLI vim edits the resolved file"

# (b) resolution is CONTEXT-DIR aware: from wt/sub, `jab vim a.txt` hits the
#     SAME file (argRel resolves against the invocation cwd).
: > "$WORK/vim.args"
( cd "$WT/sub" && "$JABC" vim a.txt ) >"$WORK/v2.out" 2>&1 \
    || _fail "(b) jab vim a.txt (from sub/) exited non-zero: $(cat "$WORK/v2.out")"
grep -qx "$WT/sub/a.txt" "$WORK/vim.args" \
    || _fail "(b) context-dir resolve missed: $(cat "$WORK/vim.args" 2>/dev/null)"
echo "ok   (b) CLI vim resolves against the invocation dir"

# (c) `jab nvim` runs the binary named `nvim` — the editor IS the verb's name.
( cd "$WT" && "$JABC" nvim doc.txt ) >"$WORK/v3.out" 2>&1 \
    || _fail "(c) jab nvim doc.txt exited non-zero: $(cat "$WORK/v3.out")"
grep -qx "$WT/doc.txt" "$WORK/nvim.args" 2>/dev/null \
    || _fail "(c) nvim did not run the nvim binary on doc.txt"
grep -q 'EDITED-BY-NVIM' "$WT/doc.txt" || _fail "(c) fake nvim did not edit doc.txt"
echo "ok   (c) nvim alias runs the nvim binary"

# (d) a `..` climb must REFUSE (NAVESCAPE) and run NO editor.
: > "$WORK/vim.args"
if ( cd "$WT" && "$JABC" vim ../../outside.txt ) >"$WORK/v4.out" 2>&1; then
    _fail "(d) vim ../../outside.txt exited 0 (escaped the tree): $(cat "$WORK/v4.out")"
fi
[ ! -s "$WORK/vim.args" ] || _fail "(d) the editor RAN on an escape path: $(cat "$WORK/vim.args")"
[ ! -f "$WORK/outside.txt" ] && [ ! -f "$TMP/$$/bro/outside.txt" ] || _fail "(d) escape created a file"
echo "ok   (d) vim ../../x refused (NAVESCAPE), no editor spawned"

# (e) bare CLI `jab vim` (no arg, no context) must refuse with VIMNONE.
if ( cd "$WT" && "$JABC" vim ) >"$WORK/v5.out" 2>&1; then
    _fail "(e) bare jab vim exited 0: $(cat "$WORK/v5.out")"
fi
grep -q 'VIMNONE\|no file' "$WORK/v5.out" || _fail "(e) bare vim: wrong refusal: $(cat "$WORK/v5.out")"
echo "ok   (e) bare CLI vim refuses (no context path)"

# --- leg 2: the pager editor edge (in-process pty, the pty.js model) --------
"$JABC" "$_CASE/vim_pty.js" "$BEDIR/views/bro/pager.js" >"$WORK/p.out" 2>"$WORK/p.err" || {
    echo "--- stderr ---"; cat "$WORK/p.err"; _fail "vim_pty exited non-zero"; }
if grep -q '^FAIL' "$WORK/p.out"; then
    echo "--- pty out ---"; cat "$WORK/p.out"; _fail "vim_pty check(s) failed"; fi
grep -q '^DONE' "$WORK/p.out" || { echo "--- pty out ---"; cat "$WORK/p.out"; _fail "vim_pty did not finish"; }
echo "ok   pager :vim suspends raw mode, drives the editor, resumes + re-drives"

# --- leg 3: full stack over a real pty (python pty.fork) --------------------
# Modes: launch = BE-048 arg-path context; nav = BE-047 nav'd file; auth =
# BE-048 authority-only guard.  doc.txt resets before each edit mode so the
# marker can only come from THAT mode's editor run.
_ptyleg() {  # _ptyleg MODE LABEL
    python3 "$_CASE/edit.py" "$JABC" "$WT" "$1" >"$WORK/e-$1.out" 2>"$WORK/e-$1.err" || {
        echo "--- stderr ---"; cat "$WORK/e-$1.err"
        echo "--- out ---";    cat "$WORK/e-$1.out"; _fail "edit.py $1 checks failed"; }
    grep -q '^DONE' "$WORK/e-$1.out" || { echo "--- out ---"; cat "$WORK/e-$1.out"; _fail "edit.py $1 did not finish"; }
    echo "ok   $2"
}
if command -v python3 >/dev/null 2>&1 && python3 -c "import pty,select" 2>/dev/null; then
    printf 'ORIGINAL\n' > "$WT/doc.txt"
    _ptyleg launch "full-stack LAUNCH context (jab cat f + bare :vim/:diff/:why target f)"
    grep -q 'EDITED-BY-VIM' "$WT/doc.txt" || _fail "(launch) the editor edit did not land in doc.txt"
    printf 'ORIGINAL\n' > "$WT/doc.txt"
    _ptyleg nav "full-stack NAV'D view :vim (nav context wins over the launch arg)"
    grep -q 'EDITED-BY-VIM' "$WT/doc.txt" || _fail "(nav) the editor edit did not land in doc.txt"
    grep -q 'EDITED-BY-VIM' "$WT/other.txt" && _fail "(nav) the editor hit the LAUNCH arg, not the nav'd file"
    : > "$WORK/vim.args"
    _ptyleg auth "authority-only //wt launch: no phantom path (:vim dir err, :diff tree-wide)"
    grep -qx "$WT" "$WORK/vim.args" \
        || _fail "(auth) bare :vim on //wt should target the wt DIR, got: $(cat "$WORK/vim.args")"
else
    echo "bro/vim: SKIP leg 3 — no python3/pty" >&2
fi

echo "PASS [bro/$NAME]"
