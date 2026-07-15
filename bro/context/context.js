//  test/bro/context/context.js — BRO-024 headless checks: the pager CONTEXT is
//  REDUCED to `//WT/dir` (the nav framework's $PWD) and the address bar renders
//  the prompt-like INVITE `//WT/dir/: <spell>`.  Asserts (the 2026-07-12 ruling):
//    (a) the context NEVER retains a `?rev`/`#hash` after a navigation, and a
//        nav to a FILE contributes the file's DIR (the file rides as the arg);
//    (b) the address-bar frame renders the `//WT/dir/: ` invite, the typed /
//        current spell RIGHT of the colon;
//    (c) `..` climbs one dir and CLAMPS at the `//WT` root (no worktree escape);
//    (d) a DELETED context dir paints the invite red (ANSI), no crash;
//    (e) DIS-061 — a BARE verb call NEVER welds an implied subject into the
//        spell (the pager composes context+verb+args ONLY); the current file
//        rides the ambient be.prev_uri stash (_prevUri, ?rev/#L stripped) that
//        a FILE-focused verb resolves in its own handler; (f) an ambiguous/dir
//        view stashes nothing;
//    (g-j) iteration 3 — a view RECORDS its full invocation {context, verb,
//        args as entered}: the bar shows it, back/refresh replay IT (rest args
//        + implied arg0 included), and a MUTATION verb is never re-executed.
//  argv[2] = views/bro/pager.js.  $SRC_ROOT (run.sh) hosts the fixture hive:
//  SRC_ROOT/WT is an anchored worktree (`.be/` shield) holding dog/DOG.h — so
//  `//WT/...` context paths resolve + stat like a real cell.
"use strict";
const pager = require(process.argv[2]);

function w(s) { const b = utf8.Encode(s); const x = io.buf(b.length + 8); x.feed(b); io.writeAll(1, x); }
function check(name, cond, got) {
  w((cond ? "ok   " : "FAIL ") + name + (cond ? "" : "   got " + JSON.stringify(got)) + "\n");
}

const SRC = io.getenv("SRC_ROOT") || "";

const realSize = tty.size;
tty.size = function () { return { rows: 24, cols: 80 }; };

function hunk(uri, text) {
  return { uri: uri, verb: "hunk", text: utf8.Encode(text || "x\n"),
           toks: new Uint32Array(0), kind: "file" };
}
function mkPager(color, gen) {
  const rec = { drove: "", ctx: undefined };
  const p = new pager.Pager(-1, { color: !!color,
    isVerb: function (v) {
      return v === "status" || v === "cat" || v === "ls" || v === "diff" ||
             v === "vim" || v === "why" || v === "put";
    },
    isMutation: function (v) { return v === "put"; },
    driveSpell: function (s, c2) {
      rec.drove = s; rec.ctx = c2;
      return gen ? gen(s) : [hunk(s)];
    } });
  p.setHunks([hunk("start.txt#L1", "hello\n")]);
  p.rec = rec;
  return p;
}

//  --- (a) REDUCTION: a nav to a FILE with ?rev#hash keeps NONE of it ----------
const p = mkPager(false);
p._runSpell("cat //WT/dog/DOG.h?feat#L5");            // a click/follow navigation
let c = p._composeCall("status");
check("ctx-file-reduces-to-dir", c.context === "//WT/dog", c.context);
check("ctx-sheds-rev", String(c.context).indexOf("?") < 0 &&
      String(c.context).indexOf("#") < 0, c.context);

//  --- (b) the address bar renders the `//WT/dir/: ` INVITE --------------------
//  scroll mode: context left of `: `, the current verb + its SHORT arg right of
//  it — the navigated FILE rides as the verb's argument (`//WT/dog/: cat DOG.h`).
const rows = p.rows(80);
const barS = p._statusLine(rows, 0, 23, 80);
check("invite-scroll", barS.indexOf("//WT/dog/: cat DOG.h") === 0, barS);
//  command mode: the invite + the TYPED spell after the colon (`: status`).
p.mode = "command"; p.cmd = "status";
const barC = p._statusLine(rows, 0, 23, 80);
check("invite-command", barC.indexOf("//WT/dog/: status") === 0, barC);
p.mode = "scroll"; p.cmd = "";

//  a `?ref` slot-edit may ride the VIEW's own uri, never the context
p._applySpell("?feat");
c = p._composeCall("status");
check("ctx-slotedit-sheds-rev", c.context === "//WT/dog", c.context);

//  --- (c) `..` climbs one dir and CLAMPS at the `//WT` root -------------------
p._applySpell("..");
c = p._composeCall("status");
check("dotdot-up", c.context === "//WT", c.context);
p._applySpell("..");
c = p._composeCall("status");
check("dotdot-clamps-at-root", c.context === "//WT", c.context);

//  --- (e) DIS-061: a BARE verb call welds NOTHING; the file rides the stash ---
//  a single-file view: `:vim` drives a BARE `vim` (no welded arg0) and the open
//  file lands in be.prev_uri (normalized — its ?rev/#L stripped) for the verb to
//  resolve; the context stays the reduced dir, untouched.
const ps = mkPager(false);
ps._runSpell("cat //WT/dog/DOG.h?feat#L5");
check("imply-stash-file", ps._prevUri() === "//WT/dog/DOG.h", ps._prevUri()); // file in the stash
ps._applySpell("vim");                               // bare: NEVER welds the subject
check("imply-single-file", ps.rec.drove === "vim", ps.rec.drove);
const barI = ps._statusLine(ps.rows(80), 0, 23, 80); // the invite shows the BARE call
check("imply-invite", barI.indexOf("//WT/dog/: vim") === 0 && barI.indexOf("DOG.h") < 0, barI);
c = ps._composeCall("status");                       // a verb call never navigates
check("imply-ctx-unmoved", c.context === "//WT/dog", c.context);
ps._applySpell("why other.c");                       // explicit args NEVER overridden
check("imply-not-on-args", ps.rec.drove === "why other.c", ps.rec.drove);

//  --- (f) an AMBIGUOUS view implies NOTHING -----------------------------------
//  multi-file view (status/multi-diff shape): bare verb runs with no arg.
const pm = mkPager(false, function () {
  return [hunk("cat //WT/dog/A.h"), hunk("cat //WT/dog/B.h")];
});
pm._runSpell("diff //WT/dog/A.h");                   // pushes the TWO-file view
pm._applySpell("vim");
check("imply-multi-none", pm.rec.drove === "vim", pm.rec.drove);
//  a dir view (ls shape): a DIR is no file subject either.
const pd = mkPager(false, function () { return [hunk("ls //WT/dog")]; });
pd._runSpell("ls //WT/dog");
pd._applySpell("vim");
check("imply-dir-none", pd.rec.drove === "vim", pd.rec.drove);

//  --- (g) iteration 3: a view records its FULL invocation ---------------------
//  the live bug: `:diff dog/DOG.h` rendered the file diff but the bar read
//  `//WT/: diff` (arg gone) and back/R re-derived a BARE `diff` (full tree).
const pg = mkPager(false);
pg._runSpell("ls //WT");                             // nav: ctx = //WT
pg._applySpell("diff dog/DOG.h");                    // typed verb call + path arg
let barG = pg._statusLine(pg.rows(80), 0, 23, 80);
check("record-bar-arg", barG.indexOf("//WT/: diff dog/DOG.h") === 0, barG);
pg.rec.drove = ""; pg.rec.ctx = undefined;
pg._refresh();                                       // R replays THE RECORDED spell
check("record-refresh-file", pg.rec.drove === "diff dog/DOG.h", pg.rec.drove);
check("record-refresh-ctx", pg.rec.ctx === "//WT", pg.rec.ctx);
pg._runSpell("cat //WT/dog/DOG.h");                  // descend one more view
pg.rec.drove = "";
pg.key(0x2d);                                        // back → the recorded file diff
check("record-back-file", pg.rec.drove === "diff dog/DOG.h", pg.rec.drove);
check("record-back-ctx", pg._composeCall("status").context === "//WT",
      pg._composeCall("status").context);

//  --- (h) REST args survive the bar and the replay (BRO-015's grep loss) ------
const ph = mkPager(false);
ph._runSpell("ls //WT");
ph._applySpell("why pat dog/DOG.h");                 // verb + arg0 + a REST arg
barG = ph._statusLine(ph.rows(80), 0, 23, 80);
check("record-rest-bar", barG.indexOf("//WT/: why pat dog/DOG.h") === 0, barG);
ph.rec.drove = "";
ph._refresh();
check("record-rest-refresh", ph.rec.drove === 'why("pat","dog/DOG.h")', ph.rec.drove);

//  --- (i) DIS-061: a bare verb call records the BARE spell (stable replay) -----
//  no implied arg0 is welded, so back/refresh replay the same bare `vim` (the
//  file rides be.prev_uri, recomputed on each view change).
const pi = mkPager(false);
pi._runSpell("cat //WT/dog/DOG.h?feat#L5");
pi._applySpell("vim");                               // bare, no welded subject
pi.rec.drove = "";
pi._refresh();
check("record-implied-replay", pi.rec.drove === "vim", pi.rec.drove);

//  --- (j) a MUTATION verb is NEVER re-executed by back/refresh (BRO-015) ------
const pj = mkPager(false);
pj._runSpell("ls //WT");
pj._applySpell("put dog/DOG.h");                     // a mutation's result view
pj.rec.drove = "";
pj._refresh();                                       // R keeps the hunks, no re-run
check("mutation-refresh-no-rerun", pj.rec.drove === "", pj.rec.drove);
pj._runSpell("cat //WT/dog/DOG.h");
pj.rec.drove = "";
pj.key(0x2d);                                        // back restores, no re-run
check("mutation-back-no-rerun", pj.rec.drove === "" && pj.view.hunks.length === 1,
      pj.rec.drove);

//  --- (d) a DELETED context dir paints the invite red (ANSI), no crash -------
if (SRC) {
  const pr = mkPager(true);                          // colour on: red is SGR
  pr._runSpell("cat //WT/dog/DOG.h");
  let bar = pr._statusLine(pr.rows(80), 0, 23, 80);
  check("invite-healthy-not-red", bar.indexOf("\x1b[31m") < 0, bar);
  io.unlink(SRC + "/WT/dog/DOG.h");
  io.rmdir(SRC + "/WT/dog");
  bar = pr._statusLine(pr.rows(80), 0, 23, 80);      // must render, not throw
  check("invite-red-when-missing", bar.indexOf("\x1b[31m") >= 0, bar);
} else {
  check("fixture-src-root", false, "no $SRC_ROOT");
}

tty.size = realSize;
w("DONE\n");
