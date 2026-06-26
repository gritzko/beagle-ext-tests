//  test/bro/status/check.js — BRO-008: the bro status URI keeps the SCHEME for
//  listing/query views (`ls:be/#L1`, not the ambiguous `be/#L1`) and keeps the
//  bare cat-style `<path>#L<n>` for file-content views (cat/diff/blob).
//
//  Repro of the live bug: `statusURI` stripped the scheme whenever the hunk URI
//  had a path and an empty/pure-line fragment, so `jab ls:be` showed `be/#L1`.
//  RED before the keep-scheme set, GREEN after.  The expected strings here MUST
//  stay byte-identical to C bro `BROStatusURI` (bro/BRO.c) — the parity oracle.
"use strict";

const bro = require("view/bro.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function eq(a, b, m) { if (a !== b) fail(m + ": '" + a + "' !== '" + b + "'"); }

//  { uri, want } — `want` is the exact status string `statusURI` must emit for
//  a single-line view (centre source line = 1), mirrored verbatim in C bro
//  bro/test/STATUS.c (which drives the real BROStatusURI on a 1-line hunk).
const LINE = 1;
const cases = [
  //  Listing/query views — scheme KEPT (the scheme IS the resource).
  { uri: "ls:be/",        want: "ls:be/#L1" },
  { uri: "lsr:be/",       want: "lsr:be/#L1" },
  { uri: "tree:keeper/",  want: "tree:keeper/#L1" },
  { uri: "status:sub/",   want: "status:sub/#L1" },
  //  File-content views — bare cat-style `<path>#L<n>`, NO regression.
  { uri: "cat:foo.c",                want: "foo.c#L1" },
  { uri: "diff:keeper/PROJ.c?a..b",  want: "keeper/PROJ.c#L1" },
  { uri: "blob:foo.c",               want: "foo.c#L1" },
];

for (const c of cases) {
  const hunk = { uri: c.uri };
  eq(bro.statusURI(hunk, LINE), c.want, "statusURI(" + c.uri + ")");
}

io.log("test/bro/status OK\n");
