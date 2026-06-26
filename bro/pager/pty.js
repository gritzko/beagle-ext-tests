//  test/js/bro/pager/pty.js — JAB-028 INTERACTIVE smoke test over a real pty.
//  Exercises the Pager against a tty.openpty() slave fd: enter raw mode, paint a
//  frame to the slave, read it back from the master, drive a key, repaint —
//  the same cycle Pager.run() runs, but stepped so this single-threaded test can
//  DRAIN the master between frames (a self-pty with no concurrent reader would
//  otherwise deadlock once the master buffer fills — a harness limit, not a
//  pager bug; run() itself is fine with a human draining the real terminal).
//  This is the one test that drives tty.raw/cook + render-to-a-real-tty + a key.
//  argv[2] = path to view/bro/pager.js.
"use strict";
const pager = require(process.argv[2]);

function w1(s) { const b = utf8.Encode(s); const x = io.buf(b.length + 8); x.feed(b); io.writeAll(1, x); }
function check(name, cond) { w1((cond ? "ok   " : "FAIL ") + name + "\n"); }

const pty = tty.openpty();
tty.setSize(pty.slave, 10, 40);

const initial = [{ uri: "doc.txt#L1", verb: "hunk",
  text: utf8.Encode("AAAA\nBBBB\nCCCC\nDDDD\nEEEE\nFFFF\n"),
  toks: new Uint32Array(0), kind: "file" }];

let swapped = false;
const p = new pager.Pager(pty.slave, { color: true, driveSpell: function (s) {
  if (s.indexOf("mock:") === 0) { swapped = true;
    return [{ uri: "mock.txt#L1", verb: "hunk", text: utf8.Encode("MOCKED OUTPUT\n"),
              toks: new Uint32Array(0), kind: "file" }]; }
  return [];
} });
p.setHunks(initial);

//  Drain the master into `frames` (so its buffer never fills + deadlocks the
//  slave write).  ONE read per call: the master fd is BLOCKING (not raw), so a
//  read past the pending bytes would hang forever — a single read grabs the
//  whole pending frame (a 10x40 frame is well under the 64 KiB buffer).
const rb = io.buf(1 << 16);
let frames = "";
function drain() { rb.reset(); const n = io.read(pty.master, rb);
  if (n > 0) frames += utf8.Decode(rb.data().slice()); }
//  Push a key into the master so the slave's io.read returns it; then step.
const kbuf = io.buf(16);
function send(s) { kbuf.reset(); kbuf.feed(utf8.Encode(s)); io.writeAll(pty.master, kbuf); }

const saved = tty.raw(pty.slave);
try {
  p.render(); drain();
  const frame0 = frames; frames = "";
  check("pty-painted-body", frame0.indexOf("AAAA") >= 0);
  check("pty-painted-status", frame0.indexOf("\x1b[7m") >= 0);    // inverse status bar
  check("pty-painted-banner", frame0.indexOf("doc.txt#L1") >= 0);

  //  BANNER BAND (bro hunk-header parity): the header row must be the pale-yellow
  //  band — open with the BANNER_SGR bg (`48;5;230`), space-FILL to the 40-col
  //  width (the band spans the row like core/emit.js / C bro), close with ESC[0m.
  //  A body row stays unbanded.  RED before the fix (only `[1m` bold, no fill).
  const band = p._banner(initial[0], 40);
  check("band-bg",   band.indexOf("48;5;230") >= 0);             // pale-yellow bg
  check("band-fill", band.replace(/\x1b\[[0-9;]*m/g, "").length === 40);  // to width
  check("band-close", band.slice(-4) === "\x1b[0m");             // closes the band
  check("band-text", band.indexOf("doc.txt#L1") >= 0);          // header text kept
  check("body-unbanded",                                         // body row: no band
        pager.paintRow(initial[0], 0, 4, true).indexOf("48;5;230") < 0);

  //  Drive a key (j = scroll down), re-render.
  send("j");
  const krb = io.buf(64); let n = 0;     // BRO-005: ≥ one SGR mouse seq (9 B)
  while (n === 0) n = io.read(pty.slave, krb);
  const kd = krb.data(); for (let i = 0; i < kd.length; i++) p.key(kd[i]);
  check("pty-key-scroll", p.view.scroll === 1);
  p.render(); drain(); frames = "";

  //  Address bar: ':' + a mock spell + Enter swaps the view.
  send(":mock:go\r");
  for (let r = 0; r < 12; r++) {
    krb.reset(); const m = io.read(pty.slave, krb);
    if (m > 0) { const d = krb.data(); for (let i = 0; i < d.length; i++) p.key(d[i]); }
  }
  check("pty-spell-ran", swapped === true);
  check("pty-view-swapped", p.view.hunks.length === 1 && p.view.hunks[0].uri === "mock.txt#L1");
  p.render(); drain();
  check("pty-painted-mock", frames.indexOf("MOCKED OUTPUT") >= 0);

  //  BRO-005: a real SGR LEFT-CLICK on a `U`-tagged token navigates to ITS URI.
  //  Reset to a hunk whose body row carries a hidden `U` click-target, feed the
  //  raw `\x1b[<0;col;rowM` mouse report through the master, and assert the
  //  pager drove driveSpell with the U-target URI (the dead link now lives).
  function packTok(tag, end) { return (((tag.charCodeAt(0) - 65) & 0x1f) << 27) | (end & 0xffffff); }
  const utext = utf8.Encode("opencat:doc2.txt rest\n");    // "open"+"cat:doc2.txt"(U)+" rest\n"
  const uhunk = [{ uri: "host.txt#L1", verb: "hunk", text: utext,
                   toks: Uint32Array.from([packTok("C", 4), packTok("U", 16), packTok("S", 22)]),
                   kind: "file" }];
  let clicked = null;
  const pm = new pager.Pager(pty.slave, { color: true, driveSpell: function (s) {
    clicked = s;
    return [{ uri: s, verb: "hunk", text: utf8.Encode("OPENED VIA CLICK\n"),
              toks: new Uint32Array(0), kind: "file" }]; } });
  pm.setHunks(uhunk);
  pm.render(); drain(); frames = "";
  //  Banner is screen row 1, body is row 2; col 2 lands on "open" (the visible
  //  token before the U-target).  Feed the SGR press report over the master.
  send("\x1b[<0;2;2M");
  for (let r = 0; r < 12 && clicked === null; r++) {
    krb.reset(); const m = io.read(pty.slave, krb);
    if (m > 0) pm._feed(krb.data().slice());
  }
  check("pty-uclick-drove", clicked === "cat:doc2.txt");
  check("pty-uclick-pushed", pm.view.hunks.length === 1 && pm.view.hunks[0].uri === "cat:doc2.txt");
  pm.render(); drain();
  check("pty-uclick-painted", frames.indexOf("OPENED VIA CLICK") >= 0);

  //  BRO-005: a real WHEEL-DOWN report (button 65) scrolls.  Use the big-ish
  //  uhunk re-seeded with many lines so a scroll is observable.
  let txt = ""; for (let i = 0; i < 40; i++) txt += "row " + i + "\n";
  const pw = new pager.Pager(pty.slave, { color: true });
  pw.setHunks([{ uri: "scroll.txt#L1", verb: "hunk", text: utf8.Encode(txt),
                 toks: new Uint32Array(0), kind: "file" }]);
  pw.render(); drain();
  send("\x1b[<65;5;5M");                                   // wheel down
  for (let r = 0; r < 8 && pw.view.scroll === 0; r++) {
    krb.reset(); const m = io.read(pty.slave, krb);
    if (m > 0) pw._feed(krb.data().slice());
  }
  check("pty-wheel-down", pw.view.scroll > 0);
} finally {
  tty.cook(pty.slave, saved);
}
io.close(pty.master); io.close(pty.slave);
w1("DONE\n");
