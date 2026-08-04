#!/bin/sh
# test/todo/ci — CI-004: the BOARD's ` ∞` button and the `ci` VIEW it pushes
# (ruling 2026-08-04), driven through the REAL UI path.  Forks a pty, `exec`s the
# real `jab todo CIB` in it, finds the button on the painted frame and presses it
# with a real SGR report.  What it pins:
#   - the ∞ ends the FILE frame and the post ✓ ends the COMMIT frame (staging
#     ends in "test it", history ends in "commit it"), in the #5883a7 tone;
#   - the click PUSHES the ci view through the ordinary machinery — the bar shows
#     the plain spell `ci //CIB-001`, the banner shows the command line;
#   - the tail opens at the END, GROWS WITH NO KEYPRESS (the ~1s view tick), `r`
#     re-tails, and the settle swaps `⋯ running` for the toned PASS footer and
#     stops the ticking;
#   - the footer is RENDER-ONLY: the log file's bytes carry no trace of it.
# Registered by the be/test glob as be-js-todo-ci — no CMakeLists edit.
set -eu

_CASE=$(cd "$(dirname "$0")" && pwd)             # test/todo/ci
_ROOT=$(cd "$_CASE/../.." && pwd)                # be/test
JABC=${JABC:-${BIN:+$BIN/jab}}
JABC=${JABC:-$(command -v jab || true)}
[ -n "$JABC" ] && [ -x "$JABC" ] || { echo "todo/ci: cannot locate jab (set BIN=)" >&2; exit 2; }
BE=$JABC
BEDIR="${BEDIR:-$(cd "$_ROOT/.." && pwd)}"       # the be/ JS tree (be/test -> be/)
[ -f "$BEDIR/main.js" ] || { echo "todo/ci: SKIP — no $BEDIR/main.js" >&2; exit 0; }
[ -f "$BEDIR/shared/ci.js" ] || { echo "todo/ci: SKIP — no shared/ci.js" >&2; exit 0; }
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}"

command -v python3 >/dev/null 2>&1 || { echo "todo/ci: SKIP — no python3" >&2; exit 0; }
python3 -c "import pty,select" 2>/dev/null \
    || { echo "todo/ci: SKIP — no pty module" >&2; exit 0; }

: "${TMP:=/tmp}"; export TMP
NAME=ci
WORK="$TMP/$$/todo/$NAME"
rm -rf "$WORK"; mkdir -p "$WORK"
: > "$TMP/$$/.be" 2>/dev/null || true
ln -sfn "$BEDIR" "$TMP/$$/jsrc" 2>/dev/null || true
SCRATCH="$TMP/$$"; trap 'rc=$?; [ "$rc" = 0 ] && [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; exit $rc' EXIT

_fail() { echo "FAIL [todo/$NAME] $*" >&2; exit 1; }

# SKIP if the jab build lacks the tty binding (pre-JS-053: no pager at all).
cat > "$WORK/ttyprobe.js" <<'EOF'
"use strict";
const ok = typeof tty === "object" && typeof tty.size === "function";
const b = io.buf(8); b.feed(utf8.Encode(ok ? "yes" : "no")); io.writeAll(1, b);
EOF
HAS=$("$JABC" "$WORK/ttyprobe.js" 2>/dev/null || echo no)
[ "$HAS" = "yes" ] || { echo "todo/ci: SKIP — jab has no tty binding" >&2; exit 0; }

# --- the fixture: ONE ticket, ONE worktree, ONE detectable rung -------------
WT="$WORK/wt"; mkdir -p "$WT/.be" "$WT/todo/CIB"
cat > "$WT/todo/CIB/CIB-001.mkd" <<'EOF'
#   CIB-001: the run button
Now: OPEN
Sev: HIGH
EOF

cd "$WT"
printf 'seed\n' > a.txt
"$BE" post 'seed commit' >/dev/null 2>&1 || _fail "seed post"

# The clone resolves the store's TRUNK ref, which a bare `post` does not write.
SEED=$(grep -o '[0-9a-f]\{40\}' "$WT/.be/wtlog" | sed -n 1p)
[ -n "$SEED" ] || _fail "seed sha capture"
printf '26718JF48j\tpost\t?#%s\n' "$SEED" > "$WT/.be/refs"
mkdir -p "$WT/work/CIB-001"
( cd "$WT/work/CIB-001" && "$BE" get "file:$WT/.be?" ) >/dev/null 2>&1 \
    || _fail "CIB-001 worktree clone"

# Rung 1 of the ladder.  60 seed lines (MORE than one 24-row screen, so "the
# tail is positioned at the end" is observable) and then one line a second, so
# the view is caught mid-flight and the tail is seen GROWING without a keypress.
cat > "$WT/work/CIB-001/ci.sh" <<'EOF'
#!/bin/sh
i=0
while [ $i -lt 60 ]; do printf 'seed %02d\n' $i; i=$((i+1)); done
i=0
while [ $i -lt 8 ]; do printf 'grow %02d\n' $i; sleep 1; i=$((i+1)); done
exit 0
EOF
chmod +x "$WT/work/CIB-001/ci.sh"

# The run artefacts land under $TMP/be-ci — give the case its own so a stale
# verdict from another run can never be read as this one's.
CITMP="$WORK/citmp"; mkdir -p "$CITMP"

"$BE" todo CIB --plain >/dev/null 2>&1 || _fail "the topic list does not render"

TMP="$CITMP" python3 "$_CASE/ciclick.py" "$JABC" "$WT" >"$WORK/out" 2>"$WORK/err" || {
    echo "--- stderr ---"; cat "$WORK/err"
    echo "--- out ---";    cat "$WORK/out"; _fail "pty run-button checks failed"; }
grep -q '^DONE' "$WORK/out" || { cat "$WORK/out"; _fail "the pty driver did not finish"; }
sed 's/^/     /' "$WORK/out"

# The FOOTER is render-only: the log file the run redirected into holds the
# child's own bytes and NOTHING the view drew under them.
LOG=$(ls "$CITMP"/be-ci/*.log 2>/dev/null | sed -n 1p)
[ -n "$LOG" ] || _fail "no log file under \$TMP/be-ci"
grep -q 'grow' "$LOG" || _fail "the log file did not capture the child's output"
grep -q 'PASS\|──\|running' "$LOG" && _fail "the verdict footer leaked into the log file"
echo "     ok   footer-is-render-only"

echo "PASS [todo/$NAME]"
