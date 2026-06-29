//  test/status/colors/check.js — DIS-057: `be status --color` must paint EVERY
//  status bucket with the SAME ANSI hue native `be status` uses (dog/THEME.c
//  THEME16TBL + dog/ULOG.c ULOG_VERB_TAGS + the sniff/SNIFF.exe.c summary
//  STATUS_BUCKET tags).  Pure unit test of view/theme.js `verbPaint`/`verbReset`
//  over the THEME16 default — no tty, no `be`, no commit chain.
//
//  Per-bucket slot + SGR oracle, mirrored from the C source (file:line in the
//  comment):
//    put Y  blue        ESC[34m       (ULOG.c:1194)
//    new W  green       ESC[32m       (ULOG.c:1197)
//    mov V  cyan        ESC[36m       (ULOG.c:1200)
//    mod E  yellow      ESC[33m       (ULOG.c:1201)
//    adv Y  blue        ESC[34m       (ULOG.c:1202)
//    del X  brown-256   ESC[38;5;94m  (ULOG.c:1206)
//    mis M  bright-red  ESC[91m       (ULOG.c:1207)
//    unk Q  grey        ESC[90m       (ULOG.c:1210)
//    mrg Z  magenta     ESC[35m       (ULOG.c:1211)
//    cnf M  bright-red  ESC[91m       (== C `conf`, ULOG.c:1230)
//    pat C  bold        ESC[1m        (native summary tag, SNIFF.exe.c:421;
//                                      ULOG.c has no `pat` row verb)
//    rmv X  brown-256   ESC[38;5;94m  (DIS-057 analogy → the `del` removal
//                                      family; no native `rmv` verb)
//  RED before theme.js maps rmv/pat/cnf (rmv was cyan 'V', pat was green 'W');
//  GREEN after.  Slot letters keep JS+C single-sourced (dog/THEME is the SoT).
"use strict";

//  Require THIS worktree's view/theme.js by ABSOLUTE path derived from the
//  script's own location (process.argv[1] = <BEDIR>/test/status/colors/check.js)
//  — a bare `require("view/theme.js")` would resolve via jab's upward be/-scan,
//  which can land on a stale sibling `be` shard (e.g. /tmp/be) that predates the
//  DIS-057 buckets.  argv[1] pins us to the tree under test.
const self = process.argv[1];
const beDir = self.slice(0, self.indexOf("/test/"));   // <BEDIR>
const theme = require(beDir + "/view/theme.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function eq(a, b, m) { if (a !== b) fail(m + ": " + JSON.stringify(a) + " !== " + JSON.stringify(b)); }

const E = "\x1b[";
const t = theme.DEFAULT;            // THEME16 — the native default palette

//  [bucket, slot, openSGR] — openSGR is verbPaint's exact bytes; the close is
//  always ESC[39m (default-fg) except a bold-only slot (pat → 'C' → ESC[1m),
//  which closes with ESC[22m (theme.reset's bold-only branch).
const cases = [
  ["put", "Y", E + "34m"],
  ["new", "W", E + "32m"],
  ["mov", "V", E + "36m"],
  ["mod", "E", E + "33m"],
  ["adv", "Y", E + "34m"],
  ["del", "X", E + "38;5;94m"],
  ["mis", "M", E + "91m"],
  ["unk", "Q", E + "90m"],
  ["mrg", "Z", E + "35m"],
  ["cnf", "M", E + "91m"],
  ["pat", "C", E + "1m"],          // native summary tag — bold
  ["rmv", "X", E + "38;5;94m"],    // DIS-057 analogy → del family (brown)
];

for (const c of cases) {
  const bucket = c[0], slot = c[1], open = c[2];
  eq(theme.VERB_SLOT[bucket], slot, "VERB_SLOT[" + bucket + "]");
  eq(t.verbPaint(bucket), open, "verbPaint(" + bucket + ")");
  //  Close: bold-only slot 'C' → ESC[22m, every other (coloured fg) → ESC[39m.
  const wantClose = open === E + "1m" ? E + "22m" : E + "39m";
  eq(t.verbReset(bucket), wantClose, "verbReset(" + bucket + ")");
}

//  Every painted bucket must carry a NON-empty SGR (no bucket renders uncoloured
//  — the DIS-057 nitpick: rmv/mov/pat/mrg/cnf/unk were the at-risk ones).
const allBuckets = ["put", "new", "rmv", "mov", "mod", "pat", "mrg", "cnf",
                    "adv", "del", "mis", "unk"];
for (const b of allBuckets)
  if (t.verbPaint(b) === "") fail("bucket '" + b + "' renders UNCOLOURED (empty SGR)");

io.log("test/status/colors OK (" + cases.length + " buckets verified vs C THEME)\n");
