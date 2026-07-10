//  test/status/buttons/assert_buttons.js — BE-041 action-button asserter.
//  Loads a `jab status --tlv` capture into a HUNK ram log (the pager's own
//  hunksFromTlv path) and asserts the pager consumer contract (`_uriAt`):
//    * every hidden `O` token immediately follows its VISIBLE label token
//      (painted by the pager, skipped by plain) — `[put]` for a `put <path>`
//      spell, `[del]` for a `delete <path>` spell — and the arg is a RAW
//      wt-relative path: no //authority, no scheme, no `#rrggbb` prefix
//      (BE-039: the verb resolves, the arg stays raw);
//    * the O-spell set matches <expect-o> exactly (so ok/put/new rows carry
//      NONE — already-staged rows get no button);
//    * every hidden `U` nav is intact and matches <expect-u> (BRO-006 rows
//      unchanged), each following a visible token (never first/dangling).
//
//  Usage:  jab assert_buttons.js <tlv-file> <expect-u> <expect-o>
"use strict";

function die(msg) { throw "ASSERT-FAIL: " + msg; }   // JABCRun → nonzero exit
function tagOf(w) { return String.fromCharCode(65 + ((w >>> 27) & 0x1f)); }

const tlvPath = process.argv[2];
const expUPath = process.argv[3];
const expOPath = process.argv[4];
if (!tlvPath || !expUPath || !expOPath)
  die("usage: assert_buttons.js <tlv> <expect-u> <expect-o>");

function lines(path) {
  return utf8.Decode(io.mmap(path, "r").data())
    .split("\n").map(function (s) { return s.trim(); })
    .filter(function (s) { return s.length; });
}

//  Load the TLV 'H'-record stream into a HUNK ram log (pager.hunksFromTlv twin).
const data = io.mmap(tlvPath, "r").data();
if (!data || !data.length) die("empty tlv capture (" + tlvPath + ")");
const log = abc.ram("HUNK", data.length + 64);
log.set(data, 0);
log.buffer.watermark = data.length;
log.rewind();

const gotU = [], gotO = [];
let hunks = 0, labels = 0;
while (log.next()) {
  hunks++;
  const text = log.text.slice();
  const toks = log.toks.slice();
  for (let i = 0; i < toks.length; i++) {
    const tag = tagOf(toks[i]);
    const lo = i > 0 ? (toks[i - 1] & 0xffffff) : 0;
    const hi = toks[i] & 0xffffff;
    if (tag === "U") {
      if (i === 0) die("hunk " + hunks + ": a U token is FIRST (nothing precedes)");
      const pt = tagOf(toks[i - 1]);
      if (pt === "U" || pt === "O") die("hunk " + hunks + ": U follows a hidden token");
      if (hi <= lo) die("hunk " + hunks + ": empty U span");
      gotU.push(utf8.Decode(text.slice(lo, hi)));
      continue;
    }
    if (tag !== "O") continue;
    //  The pager's click contract: the token BEFORE the O is the click target —
    //  it must be the VISIBLE label (not another hidden token).
    if (i === 0) die("hunk " + hunks + ": an O token is FIRST (no label precedes)");
    const ptag = tagOf(toks[i - 1]);
    if (ptag === "U" || ptag === "O")
      die("hunk " + hunks + ": O follows a HIDDEN token (tag " + ptag + "), not a visible label");
    const plo = i > 1 ? (toks[i - 2] & 0xffffff) : 0;
    const label = utf8.Decode(text.slice(plo, lo));
    if (hi <= lo) die("hunk " + hunks + ": empty O span");
    const spell = utf8.Decode(text.slice(lo, hi));
    //  Label ↔ spell verb pairing: `[put]` fronts `put <path>`, `[del]` fronts
    //  `delete <path>` (the delete verb unstages the gone file).
    const sp = spell.indexOf(" ");
    const verb = sp > 0 ? spell.slice(0, sp) : "";
    const want = verb === "put" ? "[put]" : verb === "delete" ? "[del]" : null;
    if (want === null)
      die("hunk " + hunks + ": O spell " + JSON.stringify(spell) + " is not `put|delete <path>`");
    if (label !== want)
      die("hunk " + hunks + ": O's visible label is " + JSON.stringify(label) + ", not " + JSON.stringify(want));
    labels++;
    const arg = spell.slice(sp + 1);
    if (!arg.length || arg.indexOf("//") >= 0 || arg.indexOf(":") >= 0 || arg[0] === "/" || arg[0] === "#")
      die("hunk " + hunks + ": O arg " + JSON.stringify(arg) + " is not RAW wt-relative (BE-039)");
    gotO.push(spell);
  }
}
if (!hunks) die("no hunks in the tlv stream");

function setCmp(got, want, what) {
  const g = got.slice().sort(), w = want.slice().sort();
  if (g.length !== w.length || g.some(function (s, i) { return s !== w[i]; }))
    die(what + " mismatch:\n  got:  " + JSON.stringify(g) + "\n  want: " + JSON.stringify(w));
}
setCmp(gotU, lines(expUPath), "U nav set");
setCmp(gotO, lines(expOPath), "O button-spell set");
if (labels !== gotO.length) die("label/O count skew: " + labels + " vs " + gotO.length);

io.log("OK: " + gotO.length + " action buttons + " + gotU.length +
       " U navs over " + hunks + " hunk(s)\n");
