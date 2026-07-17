//  test/js/bro/altscreen/alt.js — BRO-027 the pager brackets its raw-mode
//  session in the xterm ALTERNATE SCREEN buffer (terminfo smcup/rmcup):
//  ESC[?1049h is the FIRST byte run() writes (before hide-cursor/mouse-on),
//  ESC[?1049l the LAST (after mouse-off/SGR-reset/show-cursor, NO final clear),
//  and a throw mid-loop still restores via the existing finally.  Drives the
//  REAL Pager.run() over a tty.openpty() slave: a render hook pushes "q" into
//  the master AFTER run() has entered raw mode (pre-loading before run() is
//  racy — tty.raw flushes already-queued input; only in-flight bytes survive),
//  so the loop paints one frame, reads the q, and exits — then the master is
//  drained and the whole session byte-stream is asserted.
//  argv[2] = path to views/bro/pager.js.
"use strict";
const pager = require(process.argv[2]);

function w1(s) { const b = utf8.Encode(s); const x = io.buf(b.length + 8); x.feed(b); io.writeAll(1, x); }
function check(name, cond) { w1((cond ? "ok   " : "FAIL ") + name + "\n"); }

const ALT_ON = "\x1b[?1049h", ALT_OFF = "\x1b[?1049l";
const HIDE_CUR = "\x1b[?25l", SHOW_CUR = "\x1b[?25h", MOUSE_OFF = "\x1b[?1000l";

const pty = tty.openpty();
tty.setSize(pty.slave, 10, 40);

//  Drain the master.  Pty output lands ASYNCHRONOUSLY (kernel flip buffer), so
//  one read can miss the tail under load: after the session, a SENTINEL is
//  written to the SLAVE (FIFO — it arrives after every session byte) and the
//  master is block-read until the sentinel shows; then it is stripped.
const SENT = "\x07ALT-DONE\x07";
const rb = io.buf(1 << 16);
let frames = "";
function drain() { rb.reset(); const n = io.read(pty.master, rb);
  if (n > 0) frames += utf8.Decode(rb.data().slice()); }
const sb = io.buf(32);
function drainSession() {
  sb.reset(); sb.feed(utf8.Encode(SENT)); io.writeAll(pty.slave, sb);
  let guard = 0;
  while (frames.indexOf(SENT) < 0 && guard++ < 1000) drain();
  frames = frames.slice(0, frames.indexOf(SENT));
}
const kbuf = io.buf(16);
function send(s) { kbuf.reset(); kbuf.feed(utf8.Encode(s)); io.writeAll(pty.master, kbuf); }

const hunks = [{ uri: "doc.txt#L1", verb: "hunk",
  text: utf8.Encode("AAAA\nBBBB\nCCCC\n"),
  toks: new Uint32Array(0), kind: "file" }];

//  --- 1. a full run() session: ?1049h first, ?1049l last ---------------------
const p = new pager.Pager(pty.slave, { color: true });
p.setHunks(hunks);
//  Inject the quit key from INSIDE the loop (post-raw): first render sends "q".
const realRender = p.render.bind(p);
let sent = false;
p.render = function () { realRender(); if (!sent) { sent = true; send("q"); } };
p.run();
drainSession();
check("alt-enter-first", frames.indexOf(ALT_ON) === 0);
check("alt-enter-before-hidecur",
      frames.indexOf(HIDE_CUR) > 0 && frames.indexOf(ALT_ON) < frames.indexOf(HIDE_CUR));
check("alt-exit-present", frames.lastIndexOf(ALT_OFF) >= 0);
check("alt-exit-last", frames.slice(-ALT_OFF.length) === ALT_OFF);
check("alt-exit-after-mouseoff", frames.lastIndexOf(MOUSE_OFF) < frames.lastIndexOf(ALT_OFF));
check("alt-exit-after-showcur", frames.lastIndexOf(SHOW_CUR) < frames.lastIndexOf(ALT_OFF));
check("alt-session-painted", frames.indexOf("AAAA") > 0);   // the session did render

//  --- 2. a THROW mid-loop still restores (rides the run() finally) -----------
frames = "";
const p2 = new pager.Pager(pty.slave, { color: true });
p2.setHunks(hunks);
p2.render = function () { throw new Error("boom"); };
let threw = false;
try { p2.run(); } catch (e) { threw = true; }
drainSession();
check("alt-throw-propagates", threw === true);
check("alt-throw-restores", frames.slice(-ALT_OFF.length) === ALT_OFF);

io.close(pty.master); io.close(pty.slave);
w1("DONE\n");
