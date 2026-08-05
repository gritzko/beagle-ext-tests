//  test/bro/resize/resize.js — BRO-045: the pager REPAINTS on a terminal
//  resize with NO keystroke.  A REAL Pager.run() session over a tty.openpty()
//  slave: a render hook resizes the pty (tty.setSize) right after a frame is
//  painted and sends NOTHING; the key spin must leave on the size change (as it
//  already leaves on a tick deadline / a CI-badge flip) and paint the next
//  frame at the NEW geometry.  Both axes: frame 2 proves a cols change (the
//  status line is _fit to cols), frame 3 a rows-ONLY change (viewRows = rows-1
//  CRLFs).  The scroll position must survive both.  Only the LAST render sends
//  "q", so before BRO-045 the session HANGS in the spin — run.sh bounds it.
//  argv[2] = path to views/bro/pager.js.
"use strict";
const pager = require(process.argv[2]);

function w1(s) { const b = utf8.Encode(s); const x = io.buf(b.length + 8); x.feed(b); io.writeAll(1, x); }
function check(name, cond) { w1((cond ? "ok   " : "FAIL ") + name + "\n"); }

const ESC = "\x1b";
const CLEAR = ESC + "[2J" + ESC + "[H";

const pty = tty.openpty();
tty.setSize(pty.slave, 10, 40);

//  Drain the master (same shape as test/bro/altscreen/alt.js): pty output lands
//  asynchronously, so a SENTINEL is written to the SLAVE after the session and
//  the master is block-read until it shows, then stripped.
const SENT = "\x07RESIZE-DONE\x07";
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

//  30 short lines: enough body that scroll=3 is legal at 10 AND 16 rows.
let body = "";
for (let i = 0; i < 30; i++) body += "line" + i + "\n";
const hunks = [{ uri: "doc.txt#L1", verb: "hunk",
  text: utf8.Encode(body), toks: new Uint32Array(0), kind: "file" }];

const p = new pager.Pager(pty.slave, { color: false });
p.setHunks(hunks);
const realRender = p.render.bind(p);
let painted = 0;
p.render = function () {
  realRender();
  painted++;
  //  NO key is ever sent for the resizes — the spin must wake by itself.
  if (painted === 1) { p.view.scroll = 3; tty.setSize(pty.slave, 10, 72); }
  else if (painted === 2) { tty.setSize(pty.slave, 16, 72); }
  else if (painted === 3) { send("q"); }
};
p.run();
drainSession();

//  Frames are CLEAR-delimited; parts[0] is the run() prelude (ALT_ON etc).
const parts = frames.split(CLEAR);
//  The LAST frame carries run()'s restore bracket (mouse-off/paste-off/SGR/
//  show-cursor/ALT_OFF) glued to its status line; strip a trailing CSI run.
const TAIL = /(\x1b\[[?0-9;]*[a-zA-Z])+$/;
function geom(f) {
  if (f === undefined) return null;
  f = f.replace(TAIL, "");
  const seg = f.split("\r\n");
  //  viewRows CRLFs + the status line => seg.length === the terminal rows.
  return { rows: seg.length, cols: seg[seg.length - 1].length };
}
const g1 = geom(parts[1]), g2 = geom(parts[2]), g3 = geom(parts[3]);
w1("frames=" + (parts.length - 1) + " g1=" + JSON.stringify(g1) +
   " g2=" + JSON.stringify(g2) + " g3=" + JSON.stringify(g3) + "\n");

check("first-frame-40x10", g1 !== null && g1.cols === 40 && g1.rows === 10);
check("cols-resize-repaints-with-no-key", g2 !== null && g2.cols === 72);
check("rows-only-resize-repaints", g3 !== null && g3.rows === 16 && g3.cols === 72);
check("scroll-survives-resize", p.view.scroll === 3);
check("painted-three-frames", painted === 3);

io.close(pty.master); io.close(pty.slave);
w1("DONE\n");
