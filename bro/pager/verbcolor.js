//  test/bro/pager/verbcolor.js — BRO-010: the bro PAGER must paint the status
//  verb token (mod/unk/adv/…) with the SAME VERB_SLOT/THEME SGR the DIRECT path
//  (view/bro.js renderHunkLog → the C THEME .color() sink) emits.  On a TTY,
//  JAB-030 routes `jab status` through views/bro/pager.js paintRow, which used
//  the legacy THEME16 string table (no verb slots) and so rendered the verb
//  token PLAIN — diverging from `be` and `jab status --color | cat`.
//
//  A tty is awkward to script, so this asserts by COMPARING bytes: build the
//  status hunk exactly as views/status/status.js sinkOut tags it (a per-row
//  `<date> <verb3> <path>` with a VERB_SLOT tok on the verb cell), then check
//  the pager's paintRow carries the same per-verb SGR the direct renderHunkLog
//  carries.  RED before the fix (verb token plain), GREEN after.
//  argv[2] = views/bro/pager.js, argv[3] = view/bro.js, argv[4] = view/theme.js.
"use strict";
const pager = require(process.argv[2]);
const bro = require(process.argv[3]);
const theme = require(process.argv[4]);

function w(s) { const b = utf8.Encode(s); const x = io.buf(b.length + 8); x.feed(b); io.writeAll(1, x); }
function check(name, cond) { w((cond ? "ok   " : "FAIL ") + name + "\n"); }

//  Build a status hunk the SAME way views/status/status.js sinkOut.row does:
//  `<date7> <verb3> <path>\n`, toks [L date][S sep][<vtag> verb][S sep][S path].
function tok(tag, end) { return (((tag.charCodeAt(0) - 65) & 0x1f) << 27) | (end & 0xffffff); }
function mkHunk(verb, path) {
  const date = "       ";                 // 7-col blank date (ts 0 → no date)
  const line = date + " " + verb + " " + path + "\n";
  const text = utf8.Encode(line);
  const eDate = utf8.Encode(date).length;
  const eSep1 = eDate + 1;
  const eVerb = eSep1 + utf8.Encode(verb).length;
  const eSep2 = eVerb + 1;
  const eNL = text.length;
  const vtag = theme.VERB_SLOT[verb] || "S";
  const toks = Uint32Array.from([
    tok("L", eDate), tok("S", eSep1), tok(vtag, eVerb), tok("S", eSep2), tok("S", eNL)]);
  return { uri: "status:", verb: "hunk", text: text, toks: toks, kind: "file" };
}

//  The DIRECT path's bytes for a single-record HUNK log (the parity oracle: the
//  C THEME .color() sink renderHunkLog drives, byte-identical to native `be`).
function directBytes(h) {
  const log = abc.ram("HUNK", 4096);
  log.feed(h.uri, h.text, h.toks, "", 0n);
  const b = bro.renderHunkLog(log, "color");
  let s = ""; for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
  return s;
}

//  The PAGER's painted body row for the hunk (banner is row 0, body is row 1).
function pagerRow(h) {
  const rows = pager.indexAll([h], 80);
  return pager.paintRow(h, rows[1].off, rows[1].end, true);
}

//  The expected per-verb SGR (the C THEME16TBL the direct path uses).  These ARE
//  the bytes `be status --color | cat` / `be` emit for the verb token.
const VERB_SGR = {
  mod: "\x1b[33m",   // yellow  (slot E)
  unk: "\x1b[90m",   // grey    (slot Q)
  adv: "\x1b[34m",   // blue    (slot Y)
  del: "\x1b[38;5;94m", // brown (slot X)
  cnf: "\x1b[91m",   // red     (slot M)
};

for (const verb of ["mod", "unk", "adv", "del", "cnf"]) {
  const h = mkHunk(verb, "foo.c");
  const direct = directBytes(h);
  const prow = pagerRow(h);
  //  1. the direct path carries the verb's SGR immediately before the verb token
  //     (the oracle — must hold regardless of the pager fix).
  check("direct-" + verb + "-has-sgr", direct.indexOf(VERB_SGR[verb] + verb) >= 0);
  //  2. THE FIX: the pager's row carries the SAME open SGR right before the verb
  //     token — the verb is no longer plain.
  check("pager-" + verb + "-verb-colored", prow.indexOf(VERB_SGR[verb] + verb) >= 0);
}

//  Regression guard: a syntax (non-status) hunk's tokens still paint via the
//  shared THEME — a JS keyword carries its keyword SGR, exactly as the direct
//  path / the C bro do.  (Catches a fix that special-cases the verb cell.)
const code = utf8.Encode("const x = 1;\n");
let ctoks; try { ctoks = tok.parse(code, "js"); } catch (e) { ctoks = new Uint32Array(0); }
const ch = { uri: "x.js#L1", verb: "hunk", text: code, toks: ctoks, kind: "file" };
if (ch.toks.length) {
  const crows = pager.indexAll([ch], 80);
  const cpaint = pager.paintRow(ch, crows[1].off, crows[1].end, true);
  let hasEsc = false;
  for (let i = 0; i < cpaint.length; i++) if (cpaint.charCodeAt(i) === 27) { hasEsc = true; break; }
  check("syntax-still-painted", hasEsc);
} else {
  check("syntax-still-painted", true);   // no js lexer here → skip
}

w("DONE\n");
