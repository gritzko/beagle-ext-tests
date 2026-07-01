# JAB-003 test/lib/golden.sh — shared golden-snapshot assertion.
# Native `be` is retired as the oracle: converted jab verbs now emit TRUE
# HUNKS while native `be` stays columnar, so jab-vs-be is phased out.  A case
# runs jab, pipes stdout here, and diffs it against a committed per-case golden
# generated from jab's own verified-correct output.  No native `be` run.
#
# CONVENTION: the golden file is a committed file on disk named
#   <case_dir>/golden.out            (one assert per case)
#   <case_dir>/<NAME>.golden.out     (a case with several asserts: pass NAMEs)
# The caller spells the path explicitly as the GOLDEN_FILE arg, so the layout
# is the caller's choice; the helper only reads/writes it.
#
# USAGE (captured jab stdout on stdin):
#   "$JABC" delete a.txt 2>&1 | golden_assert file "$_CASE/golden.out"
# REGEN: run the case with GOLDEN_REGEN=1 (or when the golden is missing) to
# WRITE the normalised text as the golden and PASS; otherwise DIFF stdin vs the
# golden and FAIL (with a readable diff) on mismatch.

# JAB-003: normalise ONLY the volatile leading wall-clock date column to `T `;
# the hunk banner + trailing blank are kept — the golden captures jab verbatim.
golden_norm() { sed -E 's/^ *[0-9]{1,2}:[0-9]{2} +/T /'; }

# golden_assert NAME GOLDEN_FILE  (reads captured jab stdout on stdin)
golden_assert() {
    _g_name=$1; _g_file=$2
    _g_got="$WORK/$_g_name.golden.got"
    golden_norm >"$_g_got"
    if [ -n "${GOLDEN_REGEN:-}" ] || [ ! -f "$_g_file" ]; then
        cp "$_g_got" "$_g_file"
        echo "golden: wrote $_g_file [$_g_name]" >&2
        return 0
    fi
    if cmp -s "$_g_got" "$_g_file"; then
        return 0
    fi
    echo "--- golden ($_g_file) ---"; cat "$_g_file" >&2
    echo "--- got (normalised) ---"; cat "$_g_got" >&2
    echo "--- diff (golden vs got) ---"; diff "$_g_file" "$_g_got" >&2 || true
    _fail "golden mismatch [$_g_name] (set GOLDEN_REGEN=1 to re-snapshot)"
}
