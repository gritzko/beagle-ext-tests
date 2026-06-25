#!/bin/sh
# JAB-004 (absorbs JSQUE-015) parity case: recursive submodule `be status` via
# the resident loop — full-line byte parity, native bare `be --plain` (the
# RECURSING producer) and native `be status --plain` (the NON-recursing verb)
# vs the loop's `jab loop.js status …` (SUT=loop).  This gates the in-process
# sub-row recursion that replaced status.js's fork-per-sub (`runStatusIn` +
# `relaySub` + `/tmp` tmpfile + `readlink /proc` + `sh -c`).
#
# Pure `be` (no git, no ssh, no wire): a parent repo with a real MOUNTED sub
# (a `<wt>/<sub>/.be` redirect anchor + a committed 160000 gitlink), built the
# same way as test/all/03-staged-sub-unk but COMMITTED so the gitlink is in the
# baseline tree (a clean mounted sub native recurses into).  Native and JS get
# byte-identical, fully-isolated fixtures (separate stores), so the only
# variable is which status path renders.  Covered legs:
#   1. CLEAN sub   — the empty-but-present `status:<sub>` hunk (header + a
#      pure-`ok` summary, NO rows) + the trailing blank-line separator.
#   2. DIRTY sub   — path-PREFIXED `mod`/`unk` rows under `status:<sub>` + the
#      sub's own `?<branch>` summary (the branch token NOT prefixed).
#   3. NON-recurse — `be status --plain` (no --sub) emits ONLY the parent hunk.
# All three assert against native, so a hunk-ordering / separator / branch-token
# / prefix regression fails loudly.
. "$(dirname "$0")/../../lib/parity.sh"

# --- mounted-sub fixture builder (pure be) ----------------------------
# build_fixture <parent-wt> — under $WORK, mint an isolated sub store + a
# parent wt that MOUNTS + COMMITS it as a gitlink at vendor/sub.  Each call
# uses a store dir keyed by the wt basename so native + JS never collide.
build_fixture() {
    _pwt=$1
    _key=$(basename "$_pwt")
    # Each side gets a FULLY ISOLATED store, but the sub's PROJECT name (the
    # last store-path segment, which surfaces as the `?/<project>` summary
    # branch token) must be IDENTICAL on both sides for byte parity — so the
    # substore dir basename is the constant `substore`, only its PARENT dir is
    # keyed per side.
    _substore="$WORK/$_key/substore"
    rm -rf "$_pwt" "$WORK/$_key"
    mkdir -p "$_substore/.be" "$_pwt/.be"

    # sub store: two tracked files, one commit.
    ( cd "$_substore"
      printf 'sub payload\n' > lib.c
      printf 'sub helper\n'  > helper2.c
      "$BE" put lib.c helper2.c >/dev/null 2>&1
      "$BE" post '#sub initial' >/dev/null 2>&1 ) || _fail "sub setup ($_key)"
    _subtip=$(awk -F'\t' '$2=="post"{l=$3} END{h=l;sub(/^.*#/,"",h);print h}' \
                  "$_substore/.be/wtlog")
    case "$_subtip" in
        ????????????????????????????????????????) ;;
        *) _fail "sub tip not 40-hex ($_key): '$_subtip'" ;;
    esac

    # parent store: main.c baseline.
    ( cd "$_pwt"
      printf 'int main(void){return 0;}\n' > main.c
      "$BE" put main.c          >/dev/null 2>&1
      "$BE" post '#parent main' >/dev/null 2>&1 ) || _fail "parent setup ($_key)"

    # Mount the sub: .gitmodules + the redirect `.be` anchor (a `get` row whose
    # fragment is the sub tip — the exact shape a sub-mount writes), check the
    # sub files out on disk, then stage + COMMIT the gitlink into the baseline
    # tree so native recurses into it.
    ( cd "$_pwt"
      cat > .gitmodules <<EOF
[submodule "vendor/sub"]
	path = vendor/sub
	url = file://$_substore/.be?/substore
EOF
      mkdir -p vendor/sub
      _ronts=$(awk -F'\t' 'NR==1{print $1; exit}' .be/wtlog)
      printf '%s\tget\tfile:%s/.be/?/substore#%s\n' \
          "$_ronts" "$_substore" "$_subtip" > vendor/sub/.be
      printf 'sub payload\n' > vendor/sub/lib.c
      printf 'sub helper\n'  > vendor/sub/helper2.c
      "$BE" put .gitmodules >/dev/null 2>&1
      "$BE" put vendor/sub  >/dev/null 2>&1
      "$BE" post '#mount sub' >/dev/null 2>&1 ) || _fail "mount ($_key)"
    grep -qE 'put[[:space:]]+vendor/sub#[0-9a-f]{40}' "$_pwt/.be/wtlog" \
        || _fail "gitlink not committed ($_key): $(cat "$_pwt/.be/wtlog")"
    [ -f "$_pwt/vendor/sub/.be" ] || _fail "sub anchor not a file ($_key)"
}

# build_deep_fixture <parent-wt> — a THREE-level mounted tree to exercise the
# DEPTH-FIRST default recursion (JAB-024): a grandchild store mounted INSIDE the
# child, which is mounted inside the parent.  Layout (committed gitlinks on every
# level, all clean): parent → vendor/sub → vendor/sub/lib/deep.  The substore /
# grandchild-store dir basenames are CONSTANT (`substore` / `gstore`) so the
# `?/<project>` summary branch token byte-matches across the native + JS sides;
# only the keyed PARENT dir differs.  Rebuilds the wt from scratch (clean state).
build_deep_fixture() {
    _pwt=$1
    _key=$(basename "$_pwt")
    # Stores live OUTSIDE the parent wt (a sibling `$_key-stores/` dir), so they
    # never surface as untracked rows in the parent's own scan — only the MOUNTED
    # checkouts under vendor/sub are part of the wt.  (build_fixture keys its
    # substore inside the wt and survives only by symmetry; the 3-level tree's
    # nested mount makes that asymmetric, so isolate the stores here.)  The store
    # basenames stay CONSTANT (`substore`/`gstore`) for the `?/<project>` token.
    _stores="$WORK/$_key-stores"
    _substore="$_stores/substore"
    _gstore="$_stores/gstore"
    rm -rf "$_pwt" "$_stores"
    mkdir -p "$_gstore/.be" "$_substore/.be" "$_pwt/.be"

    # grandchild store: one tracked file, one commit.
    ( cd "$_gstore"
      printf 'gc payload\n' > deep.c
      "$BE" put deep.c >/dev/null 2>&1
      "$BE" post '#gc initial' >/dev/null 2>&1 ) || _fail "gc setup ($_key)"
    _gtip=$(awk -F'\t' '$2=="post"{l=$3} END{h=l;sub(/^.*#/,"",h);print h}' \
                "$_gstore/.be/wtlog")

    # child store: own files + a COMMITTED grandchild gitlink at lib/deep.
    ( cd "$_substore"
      printf 'sub payload\n' > lib.c
      printf 'sub helper\n'  > helper2.c
      "$BE" put lib.c helper2.c >/dev/null 2>&1
      "$BE" post '#sub initial' >/dev/null 2>&1 ) || _fail "sub setup ($_key)"
    ( cd "$_substore"
      cat > .gitmodules <<EOF
[submodule "lib/deep"]
	path = lib/deep
	url = file://$_gstore/.be?/gstore
EOF
      mkdir -p lib/deep
      _r=$(awk -F'\t' 'NR==1{print $1; exit}' .be/wtlog)
      printf '%s\tget\tfile:%s/.be/?/gstore#%s\n' "$_r" "$_gstore" "$_gtip" \
          > lib/deep/.be
      printf 'gc payload\n' > lib/deep/deep.c
      "$BE" put .gitmodules >/dev/null 2>&1
      "$BE" put lib/deep    >/dev/null 2>&1
      "$BE" post '#mount gc' >/dev/null 2>&1 ) || _fail "gc mount ($_key)"
    _subtip=$(awk -F'\t' '$2=="post"{l=$3} END{h=l;sub(/^.*#/,"",h);print h}' \
                  "$_substore/.be/wtlog")

    # parent: main.c baseline + a COMMITTED child gitlink at vendor/sub, with the
    # child's mount AND the checked-out grandchild on disk underneath it.
    ( cd "$_pwt"
      printf 'int main(void){return 0;}\n' > main.c
      "$BE" put main.c          >/dev/null 2>&1
      "$BE" post '#parent main' >/dev/null 2>&1 ) || _fail "parent setup ($_key)"
    ( cd "$_pwt"
      cat > .gitmodules <<EOF
[submodule "vendor/sub"]
	path = vendor/sub
	url = file://$_substore/.be?/substore
EOF
      mkdir -p vendor/sub/lib/deep
      _r=$(awk -F'\t' 'NR==1{print $1; exit}' .be/wtlog)
      printf '%s\tget\tfile:%s/.be/?/substore#%s\n' "$_r" "$_substore" "$_subtip" \
          > vendor/sub/.be
      printf 'sub payload\n' > vendor/sub/lib.c
      printf 'sub helper\n'  > vendor/sub/helper2.c
      cat > vendor/sub/.gitmodules <<EOF
[submodule "lib/deep"]
	path = lib/deep
	url = file://$_gstore/.be?/gstore
EOF
      printf '%s\tget\tfile:%s/.be/?/gstore#%s\n' "$_r" "$_gstore" "$_gtip" \
          > vendor/sub/lib/deep/.be
      printf 'gc payload\n' > vendor/sub/lib/deep/deep.c
      "$BE" put .gitmodules >/dev/null 2>&1
      "$BE" put vendor/sub  >/dev/null 2>&1
      "$BE" post '#mount sub' >/dev/null 2>&1 ) || _fail "sub mount ($_key)"
    [ -f "$_pwt/vendor/sub/.be" ]          || _fail "child anchor missing ($_key)"
    [ -f "$_pwt/vendor/sub/lib/deep/.be" ] || _fail "grandchild anchor missing ($_key)"
}

# recursive_parity — native bare `be --plain` (the recursing producer) vs the
# loop's `status --plain --sub`, both in-place, full-line byte parity.  `--sub`
# is now an EXPLICIT no-op (recursion is the JAB-024 default); this leg keeps the
# JAB-004 explicit-flag form green.
recursive_parity() {
    ( cd "$NAT" && "$BE" --plain ) >"$NAT.out" 2>"$NAT.err" || true
    ( cd "$JS"  && run_js status --plain --sub ) >"$JS.out" 2>"$JS.err" || true
    assert_stdout "$NAT.out" "$JS.out"
}

# default_recursive_parity (JAB-024) — native bare `be --plain` (the recursing
# producer) vs the loop's BARE `status --plain` (NO flag): the default now
# recurses into mounted subs, so a no-flag `jab status` must byte-match the
# native recursing form (parent hunk, then each mounted sub depth-first, blank-
# line separated).  This is the gate JAB-024 flips.
default_recursive_parity() {
    ( cd "$NAT" && "$BE" --plain ) >"$NAT.out" 2>"$NAT.err" || true
    ( cd "$JS"  && run_js status --plain ) >"$JS.out" 2>"$JS.err" || true
    assert_stdout "$NAT.out" "$JS.out"
}

# flat_parity — native `be status --plain` (non-recursing verb) vs the loop's
# `status --plain --nosub`: ONLY the parent hunk, no sub recursion.  Post-JAB-024
# the FLAT form is reached via `--nosub` (the default recurses), so this gates
# the suppression flag against native's flat `be status --plain`.
flat_parity() {
    ( cd "$NAT" && run_native status --plain        ) >"$NAT.out" 2>"$NAT.err" || true
    ( cd "$JS"  && run_js     status --plain --nosub ) >"$JS.out"  2>"$JS.err"  || true
    assert_stdout "$NAT.out" "$JS.out"
}

NAT="$WORK/nat"; JS="$WORK/js"
build_fixture "$NAT"
build_fixture "$JS"

# 1. CLEAN sub, EXPLICIT --sub: the empty-but-present hunk + separator
#    (JAB-004 explicit-flag form, kept green post-JAB-024).
recursive_parity
echo "ok: clean mounted-sub recursive status parity --sub (empty hunk + separator)"

# 2. CLEAN sub, DEFAULT (no flag) — JAB-024: a bare `jab status` recurses,
#    byte-matching native bare `be --plain`.  This is the new default-gate.
default_recursive_parity
echo "ok: clean mounted-sub DEFAULT-recurse parity (bare jab status, JAB-024)"

# 3. --nosub suppresses recursion: parent hunk only, matching native flat
#    `be status --plain`.
flat_parity
echo "ok: --nosub flat status parity (parent hunk only)"

# 4. DIRTY sub: a tracked mod + an untracked add inside the mount → the sub
#    hunk carries path-PREFIXED rows + its own dirty summary.  Assert BOTH the
#    explicit --sub form AND the bare default recurse, plus --nosub stays flat.
for _d in "$NAT" "$JS"; do
    printf 'sub payload v2\n' > "$_d/vendor/sub/lib.c"
    printf 'NEW\n'            > "$_d/vendor/sub/newfile.c"
done
recursive_parity
echo "ok: dirty mounted-sub recursive status parity --sub (prefixed rows + summary)"
default_recursive_parity
echo "ok: dirty mounted-sub DEFAULT-recurse parity (bare jab status, JAB-024)"
flat_parity
echo "ok: dirty sub --nosub stays flat (parent hunk only)"

# 5. DEEP sub: mount a grandchild INSIDE the (clean-rebuilt) child, so the tree
#    is parent → vendor/sub → vendor/sub/lib/deep.  The bare default must recurse
#    DEPTH-FIRST through all three, byte-matching native bare `be --plain`
#    (header/summary/blank per hunk, grandchild after its parent).
build_deep_fixture "$NAT"
build_deep_fixture "$JS"
default_recursive_parity
echo "ok: deep grandchild DEFAULT-recurse parity (depth-first, JAB-024)"
recursive_parity
echo "ok: deep grandchild recursive parity --sub (depth-first)"
flat_parity
echo "ok: deep grandchild --nosub stays flat (parent hunk only)"

pass
