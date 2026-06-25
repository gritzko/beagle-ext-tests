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

  //  Drive a key (j = scroll down), re-render.
  send("j");
  const krb = io.buf(8); let n = 0;
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
} finally {
  tty.cook(pty.slave, saved);
}
io.close(pty.master); io.close(pty.slave);
w1("DONE\n");
