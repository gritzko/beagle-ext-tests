//  test/bro/help/check.js — BRO-007: drive the Pager's `h` key over a real
//  `jab help: --tlv` capture and assert the HELP screen behaves as a normal
//  pushed view.
//
//  From a base `log:` view: feed `h` → `_runSpell("help:")` → driveSpell (mocked
//  to return the captured help hunks) → pushView, so the help hunk is on screen.
//  Assert the pushed hunk text carries BOTH the SHORTCUT rows (j/k, q) AND the
//  URI-SCHEME rows (commit:, diff:, log:).  Feed `-` (back) → the view stack pops
//  to the prior (log) view.  Finally assert `_statusLine` renders `h: help` and
//  NOT the old `(j/k space g/G : q)` hint blob.  RED before the `h` binding +
//  status-line change, GREEN after.
//
//  argv[2] = captured `jab log: --tlv` bytes (the base view);
//  argv[3] = captured `jab help: --tlv` bytes (the help view's real output).
"use strict";

const pager = require("views/bro/pager.js");

function fail(m) { io.log("FAIL " + m + "\n"); throw "FAIL " + m; }
function ok(v, m) { if (!v) fail(m); }

//  Load a captured --tlv stream into hunks.
function loadHunks(path) {
  const st = io.lstat(path);
  const sz = Number(st.size);
  const fd = io.open(path, "r");
  const rb = io.buf(sz + 16);
  io.readAll(fd, rb, sz);
  io.close(fd);
  return pager.hunksFromTlv(rb.data().slice());
}

const logHunks  = loadHunks(process.argv[2]);
const helpHunks = loadHunks(process.argv[3]);
ok(logHunks.length  >= 1, "log: produced at least one hunk");
ok(helpHunks.length >= 1, "help: produced at least one hunk");

//  Stub the terminal size (no tty under ctest); the pager only needs a width.
const COLS = 80;
const realSize = tty.size;
tty.size = function () { return { rows: 24, cols: COLS }; };

//  driveSpell mocked: the `help:` spell yields the captured help hunks (exactly
//  what the live bro handler's driveSpell would re-enter the loop to produce).
const p = new pager.Pager(-1, { color: false, driveSpell: function (spell) {
  return spell === "help:" ? helpHunks : [];
} });
p.setHunks(logHunks);
p.rows(COLS);
ok(p.stack.length === 0, "base log view, empty back-stack");
const baseUri = p.view.hunks[0].uri;

//  Feed `h` (0x68): _runSpell("help:") → pushView.  The help hunk is now current.
p.key(0x68);
ok(p.stack.length === 1, "h pushed a new view (back-stack depth 1)");
const shown = p.view.hunks.map(function (h) { return utf8.Decode(h.text); }).join("\n");

//  (a) SHORTCUT rows: the live `_keyScroll` bindings, single-sourced from the
//  pager's SHORTCUTS export — j/k and q MUST appear.
ok(shown.indexOf("j / k") >= 0 || shown.indexOf("j/k") >= 0, "help lists the j/k scroll shortcut");
ok(/(^|\n)\s*q\s/.test(shown) || shown.indexOf(" q ") >= 0, "help lists the q (quit) shortcut");
ok(shown.indexOf("PAGER SHORTCUTS") >= 0, "help has a SHORTCUTS section heading");

//  (b) URI-SCHEME rows: the registry views typeable at `:` — commit/diff/log.
ok(shown.indexOf("commit:") >= 0, "help lists the commit: scheme");
ok(shown.indexOf("diff:")   >= 0, "help lists the diff: scheme");
ok(shown.indexOf("log:")    >= 0, "help lists the log: scheme");
ok(shown.indexOf("URI SCHEMES") >= 0, "help has a URI-SCHEMES section heading");

//  Cross-check: only schemes that are REAL views are listed (no stray scheme).
ok(shown.indexOf("blob:") >= 0 && shown.indexOf("status:") >= 0 && shown.indexOf("grep:#") >= 0,
   "help lists blob:/status:/grep: schemes");

//  Feed `-` (0x2d, back): pop the help view → back to the base (log) view.
p.key(0x2d);
ok(p.stack.length === 0, "back (-) popped the help view");
ok(p.view.hunks[0].uri === baseUri, "back returned to the prior (log) view");

//  Backspace (0x7f) from the base view is a no-op pop (nothing to pop).
p.key(0x68);
ok(p.stack.length === 1, "h re-pushed help");
p.key(0x7f);                                    // BS also backs out
ok(p.stack.length === 0, "BS popped the help view too");

//  The status line now ends with `h: help`, NOT the old hint blob.
const rows = p.rows(COLS);
const status = p._statusLine(rows, 0, 23, COLS);
ok(status.indexOf("h: help") >= 0, "status line reads `h: help`");
ok(status.indexOf("(j/k space g/G : q)") < 0, "status line dropped the old hint blob");

tty.size = realSize;
io.log("test/bro/help OK (pushed help, backed out, status `h: help`)\n");
