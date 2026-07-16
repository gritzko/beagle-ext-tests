#!/bin/sh
# test/sub/pinuri-legacy — DIS-072 read-compat: an EXISTING sub wtlog carrying a
# legacy synthetic-branch row `?/child/.parent#<pin>` must still PARSE (its cur
# tip resolves, the sub keeps working), and the next PARENT move RE-ANCHORS it
# by appending a fresh `//WT/path/to/sub#<newpin>` row — the old row is never
# rewritten.
. "$(dirname "$0")/../lib/subcase.sh"

# --- parent P + sub store; the sub mounted with a LEGACY synthetic row ------
mkdir -p "$WORK/storeS/.be" "$WORK/P/.be"
( cd "$WORK/storeS" && printf 'sub v1\n' > S.c && "$BE" post 'sub initial' ) >/dev/null 2>&1 \
    || _fail "storeS setup"
( cd "$WORK/P" && printf 'top v1\n' > TOP.c && "$BE" post 'parent initial' ) >/dev/null 2>&1 \
    || _fail "P setup"
S0=$(sc_tip "$WORK/storeS"); sc_is40 "$S0" "sub tip0"

mkdir -p "$WORK/P/sub"
cat > "$WORK/.legacy.js" <<'EOF'
//  DIS-072: seed a LEGACY sub anchor — row-0 redirect + `?/sub/.par#<pin>`.
const ulog = require(process.argv[2] + "/shared/ulog.js");
ulog.write(process.argv[3], [
  { verb: "get", uri: URI.make("file", undefined, process.argv[4] + "/", "/") },
  { verb: "get", uri: URI.make(undefined, undefined, undefined, "/sub/.par", process.argv[5]) },
]);
EOF
"$JABC" "$WORK/.legacy.js" "$BEDIR" "$WORK/P/sub/.be" "$WORK/storeS/.be" "$S0" \
    >/dev/null 2>&1 || _fail "could not seed the legacy anchor"
printf 'sub v1\n' > "$WORK/P/sub/S.c"
grep -q '?/sub/.par#' "$WORK/P/sub/.be" || _fail "legacy row not seeded: $(cat "$WORK/P/sub/.be")"

# --- the legacy row still PARSES: the sub's cur tip is the pin --------------
[ "$(sc_subtip "$WORK/P/sub")" = "$S0" ] \
    || _fail "legacy '?/sub/.par#pin' row no longer parses (curTip != pin)"

# commit the gitlink into P so the sub is a tracked mount.
sc_pin_gitlink "sub" "$WORK/P/.be/wtlog" "$S0"
( cd "$WORK/P" && "$BE" post 'mount sub' ) >/dev/null 2>&1 || _fail "commit sub gitlink"
[ "$(sc_gitlink_pin "$WORK/P" sub)" = "$S0" ] || _fail "build: P.sub gitlink != sub tip"

# --- advance the sub on the legacy anchor (it must keep working) ------------
printf 'sub v2 EDITED\n' > "$WORK/P/sub/S.c"
( cd "$WORK/P/sub" && "$JABC" put S.c >/dev/null 2>&1 && "$JABC" post '#s2' ) \
    >"$WORK/s2.out" 2>"$WORK/s2.err" || _fail "sub own commit failed: $(cat "$WORK/s2.err")"
S1=$(sc_subtip "$WORK/P/sub"); sc_is40 "$S1" "sub tip1"
[ "$S1" != "$S0" ] || _fail "sub commit did not advance the sub wt"

# --- the next PARENT move re-anchors: a fresh `///sub#<newpin>` row ---------
( cd "$WORK/P" && "$JABC" post '#absorb sub' ) >"$WORK/pp.out" 2>"$WORK/pp.err" \
    || _fail "parent absorb post failed: $(cat "$WORK/pp.err")"
[ "$(sc_gitlink_pin "$WORK/P" sub)" = "$S1" ] || _fail "parent post did not bump the gitlink"
ANCH=$(od -An -c "$WORK/P/sub/.be" | tr -d ' \n')
case "$ANCH" in
  *"///sub#$S1"*) ;;
  *) _fail "parent post did not re-anchor the child at ///sub#$S1: $(cat "$WORK/P/sub/.be")" ;;
esac
# read-compat is append-only: the legacy row is still there, untouched.
grep -q '?/sub/.par#' "$WORK/P/sub/.be" \
    || _fail "the legacy row was rewritten (wtlogs are append-only)"

pass
