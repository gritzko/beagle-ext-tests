//  test/ls/links/assert_u.js — BRO-006 U-target asserter for ls/lsr/tree.
//  Loads a `jab <verb> --tlv` capture into a HUNK ram log (the SAME path the
//  bro pager walks via hunksFromTlv), then for EVERY entry row asserts the
//  consumer contract `be/views/bro/pager.js _uriAt`: a visible row token is
//  immediately followed by a `U`-tagged token (tag 20) whose hidden text bytes
//  ARE the nav URI (`cat:<path>`/`ls:<sub>/` for ls/lsr, `blob:`/`tree:` for
//  tree), mirroring C `sniff/LS.c` (HUNK_NAV_CAT/LS).
//
//  Usage:  jab assert_u.js <tlv-file> <expect-file>
//    <expect-file> lines: `<navUri>` — one per entry row across ALL hunks
//    (lsr emits one hunk per directory).  The asserter collects every `U`-token
//    payload across all hunks (order-independent set compare) and checks each U
//    sits immediately after a visible (non-U) token (the row), never
//    first/dangling — a non-navigable row (tree's `..`) simply has no U.
"use strict";

function die(msg) { throw "ASSERT-FAIL: " + msg; }   // JABCRun → nonzero exit
function tagOf(w) { return String.fromCharCode(65 + ((w >>> 27) & 0x1f)); }

const tlvPath = process.argv[2];
const expPath = process.argv[3];
if (!tlvPath || !expPath) die("usage: assert_u.js <tlv> <expect>");

//  Load the TLV 'H'-record stream into a HUNK ram log (pager.hunksFromTlv twin).
const data = io.mmap(tlvPath, "r").data();
if (!data || !data.length) die("empty tlv capture (" + tlvPath + ")");
const log = abc.ram("HUNK", data.length + 64);
log.set(data, 0);
log.buffer.watermark = data.length;
log.rewind();

//  Walk every hunk, collect each U-token's decoded payload + verify it follows
//  a visible token (the pager's _uriAt: prev-token-is-visible → its [prevEnd,end)
//  bytes are the URI).
const got = [];
let hunks = 0;
while (log.next()) {
  hunks++;
  const text = log.text.slice();
  const toks = log.toks.slice();
  for (let i = 0; i < toks.length; i++) {
    if (tagOf(toks[i]) !== "U") continue;
    if (i === 0) die("hunk " + hunks + ": a U token is FIRST (no visible token precedes it)");
    if (tagOf(toks[i - 1]) === "U") die("hunk " + hunks + ": two adjacent U tokens (no row between)");
    const lo = toks[i - 1] & 0xffffff;
    const hi = toks[i] & 0xffffff;
    if (hi <= lo) die("hunk " + hunks + ": empty U token span [" + lo + "," + hi + ")");
    got.push(utf8.Decode(text.slice(lo, hi)));
  }
}
if (!hunks) die("no hunks in the tlv stream");

//  Expected nav URIs (one per entry row across all hunks), order-independent.
const want = utf8.Decode(io.mmap(expPath, "r").data())
  .split("\n").map(function (s) { return s.trim(); }).filter(function (s) { return s.length; });

got.sort();
const wantSorted = want.slice().sort();
if (got.length !== wantSorted.length)
  die("U-token count " + got.length + " != expected " + wantSorted.length +
      "\n  got:  " + JSON.stringify(got) + "\n  want: " + JSON.stringify(wantSorted));
for (let i = 0; i < got.length; i++)
  if (got[i] !== wantSorted[i])
    die("U-token mismatch:\n  got:  " + JSON.stringify(got) +
        "\n  want: " + JSON.stringify(wantSorted));

io.log("OK: " + got.length + " U click-targets over " + hunks + " hunk(s): " + JSON.stringify(got));
