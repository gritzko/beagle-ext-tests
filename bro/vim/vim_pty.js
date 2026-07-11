//  test/bro/vim/vim_pty.js — BE-047 the pager EDITOR edge, headless over a
//  tty.openpty() slave (the pty.js model).  A typed `:vim` must: (1) COOK the
//  tty before the editor spell is driven (the terminal handover), threading the
//  view context; (2) re-enter RAW after it returns; (3) RE-DRIVE the view's own
//  spell (refresh) so the edit shows.  The "editor" is the driveSpell mock
//  itself appending a line to the target file; tty.raw/tty.cook are wrapped to
//  observe the cook→drive→raw order.  argv[2] = path to views/bro/pager.js.
"use strict";
const pager = require(process.argv[2]);

function w1(s) { const b = utf8.Encode(s); const x = io.buf(b.length + 8); x.feed(b); io.writeAll(1, x); }
function check(name, cond) { w1((cond ? "ok   " : "FAIL ") + name + "\n"); }

const WORK = io.getenv("WORK") || (io.getenv("TMP") || "/tmp");
const FILE = WORK + "/pty-doc.txt";

function readF(p) {
  let st; try { st = io.lstat(p); } catch (e) { return ""; }
  const size = Number(st.size);
  if (size === 0) return "";
  const fd = io.open(p, "r");
  try { const b = io.buf(size + 16); io.readAll(fd, b, size); return utf8.Decode(b.data().slice()); }
  finally { try { io.close(fd); } catch (e) {} }
}
function writeF(p, s) {
  const fd = io.open(p, "c");
  try {
    try { io.resize(fd, 0); } catch (e) {}
    const bytes = utf8.Encode(s);
    const b = io.buf(bytes.length + 8); b.feed(bytes); io.writeAll(fd, b);
  } finally { try { io.close(fd); } catch (e) {} }
}

const pty = tty.openpty();
tty.setSize(pty.slave, 10, 40);
writeF(FILE, "LINE1\n");

//  Wrap tty.raw/cook to observe the suspend/resume dance around the editor.
let state = "cooked";
const events = [];
const realRaw = tty.raw, realCook = tty.cook;
tty.raw = function (fd) { state = "raw"; events.push("raw"); return realRaw(fd); };
tty.cook = function (fd, s) { state = "cooked"; events.push("cook"); return realCook(fd, s); };

const calls = [];
const p = new pager.Pager(pty.slave, {
  color: true,
  isTty: function (w) { return w === "vim" || w === "nvim"; },
  driveSpell: function (spell, context) {
    calls.push({ spell: spell, context: context, state: state });
    if (spell === "vim") {                       // the "editor": append a line
      writeF(FILE, readF(FILE) + "EDITED\n");
      return [];
    }
    //  the view's own spell (the refresh re-drive): the CURRENT file bytes
    return [{ uri: "doc.txt", verb: "hunk", text: utf8.Encode(readF(FILE)),
              toks: new Uint32Array(0), kind: "file" }];
  } });
p.setHunks([{ uri: "doc.txt", verb: "hunk", text: utf8.Encode("LINE1\n"),
              toks: new Uint32Array(0), kind: "file" }]);
p.view.verb = "cat"; p.view.uri = "doc.txt";     // a NAV'D view: `cat doc.txt`

//  Drain the master so its buffer never fills (the pty.js harness discipline).
const rb = io.buf(1 << 16);
function drain() { rb.reset(); try { io.read(pty.master, rb); } catch (e) {} }

p._saved = tty.raw(pty.slave);                   // mirror run()'s raw entry
try {
  p._feed(utf8.Encode(":vim\r"));                // the address bar: `:vim` Enter
  drain();

  check("edit-two-drives", calls.length === 2);
  check("edit-spell-bare-vim", calls.length > 0 && calls[0].spell === "vim");
  check("edit-context-threaded", calls.length > 0 && calls[0].context === "doc.txt");
  check("edit-tty-cooked-at-editor", calls.length > 0 && calls[0].state === "cooked");
  check("edit-refresh-redrives-view", calls.length > 1 && calls[1].spell === "cat doc.txt");
  check("edit-tty-raw-at-refresh", calls.length > 1 && calls[1].state === "raw");
  check("edit-raw-cook-raw-order", events.join(",") === "raw,cook,raw");
  check("edit-file-edited", readF(FILE).indexOf("EDITED") >= 0);
  check("edit-view-shows-edit", p.view.hunks.length === 1 &&
        utf8.Decode(p.view.hunks[0].text).indexOf("EDITED") >= 0);
  check("edit-no-push", p.stack.length === 0);   // refresh swaps IN PLACE
  check("edit-still-running", p.quit === false);
} finally {
  tty.cook = realCook; tty.raw = realRaw;
  tty.cook(pty.slave, p._saved);
}
io.close(pty.master); io.close(pty.slave);
try { io.unlink(FILE); } catch (e) {}
w1("DONE\n");
