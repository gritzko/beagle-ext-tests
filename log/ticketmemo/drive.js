//  test/log/ticketmemo/drive.js — LOG-005 repro driver: ONE resident process
//  that runs the REAL `log:` view through core/loop.js (the pager's driveSpell
//  shape) over a history whose commit summaries ALL carry a resolvable ticket
//  code.  The measure is WORK, never wall time: every `be.navCwd(<dir>)` and
//  every resolve_hash `treeAt` climb is counted off the module instances the
//  view calls through, so the assertion is implementation-blind.
//    THE LAW: the `.be` climbs of a `log:` drive are O(1) in the ROW COUNT —
//  the same drive at 4 rows and at 16 rows must pay the SAME number of climbs.
//    RED (pre-fix): shared/ticket.js:86 asks be.navCwd(projectRoot) once per
//  ticket-coded row, so the 16-row drive pays 12 climbs more than the 4-row one.
//  Second leg: dag.commitTs must parse a commit ONCE per (keeper, sha) — RED
//  today (one parseCommit per call, which the branchHistory sort pays n log n).
//  args: <project root> <jsrc dir>   (the jsrc the fixture's verbs load from —
//  the driver MUST share those module instances, so it requires through the
//  very same path and hands loop.js that root as its process.argv[1]).
"use strict";

const ROOT = args[0], JSRC = args[1];
process.argv[1] = JSRC + "/main.js";
const loop = require(JSRC + "/core/loop.js");
const discover = require(JSRC + "/core/discover.js");
const rh = require(JSRC + "/core/resolve_hash.js");
const dag = require(JSRC + "/shared/dag.js");

let fails = 0;
function ok(cond, msg) {
  if (!cond) { fails++; io.log("FAIL " + msg); } else io.log("ok   " + msg);
}

//  --- the two counters -----------------------------------------------------
//  `be.navCwd` IS discover.navCwd (mintBe folds the module onto the global), so
//  patching the export counts exactly the calls ticket.js makes; treeAt is the
//  climb underneath it — the `.be` re-parse this ticket is about.
let navs = 0, trees = 0;
const oNav = discover.navCwd, oTree = rh.treeAt;
discover.navCwd = function (dir) { if (dir) navs++; return oNav.apply(null, arguments); };
rh.treeAt = function () { trees++; return oTree.apply(null, arguments); };

//  Run the REAL verb in-process, capturing fd 1 (the driveSpell hook).
function spellRaw(argv) {
  const oWriteAll = io.writeAll, oWrite = io.write;
  const outs = [];
  io.writeAll = function (fd, b) {
    if (fd === 1) { outs.push(b.data().slice()); return; }
    if (fd === 2) return;
    return oWriteAll(fd, b);
  };
  io.write = function (fd, b) {
    if (fd === 1) { const d = b.data().slice(); outs.push(d); return d.length; }
    if (fd === 2) return;
    return oWrite(fd, b);
  };
  try { loop.cli(["jab", "loop.js"].concat(argv)); }
  finally { io.writeAll = oWriteAll; io.write = oWrite; }
  let n = 0; for (const c of outs) n += c.length;
  const all = new Uint8Array(n); let o = 0;
  for (const c of outs) { all.set(c, o); o += c.length; }
  return utf8.Decode(all);
}

//  One `log:#N` drive → { rows, navs, trees }; the counters are CUMULATIVE.
function drive(spell) {
  const n0 = navs, t0 = trees;
  const out = spellRaw([spell, "--plain"]);
  let rows = 0;
  for (const l of out.split("\n")) if (/^[0-9a-f]{8} /.test(l)) rows++;
  return { rows: rows, navs: navs - n0, trees: trees - t0, out: out };
}

io.chdir(ROOT + "/wt");
const a = drive("log:#4");
const b = drive("log:#16");
io.log("cost: 4 rows nav=" + a.navs + " treeAt=" + a.trees +
       " | 16 rows nav=" + b.navs + " treeAt=" + b.trees);

//  The fixture must actually exercise the ticket-code path, or the counts below
//  would be trivially flat: a resolvable `TKT-1` in every summary.
ok(a.rows === 4 && b.rows === 16, "the two drives render 4 and 16 rows (" +
   a.rows + "," + b.rows + ")");
ok(a.navs > 0, "the fixture reaches the ticket-code resolver (navCwd " + a.navs + ")");
ok(b.out.indexOf("TKT-1") > 0, "…and the rows carry the ticket code");

//  THE repro: 12 more rows must cost ZERO more `.be` climbs.
ok(b.navs - a.navs === 0,
   "LOG-005: navCwd climbs are O(1) in row count (4 rows " + a.navs +
   ", 16 rows " + b.navs + ")");
ok(b.trees - a.trees === 0,
   "LOG-005: treeAt `.be` re-parses are O(1) in row count (4 rows " + a.trees +
   ", 16 rows " + b.trees + ")");

//  --- leg 2: commitTs parses a commit ONCE per (keeper, sha) ---------------
//  A stand-in keeper (dag.commitTs only ever calls parseCommit) counts the
//  parses the branchHistory ts-sort pays n log n times today.
const SHA1 = "1111111111111111111111111111111111111111";
const SHA2 = "2222222222222222222222222222222222222222";
function fakeKeeper(tag) {
  return { tag: tag, n: 0,
           parseCommit: function (sha) {
             this.n++;
             return { author: "A <a@e.st> " + (sha === SHA1 ? 1700000000 : 1700000600) +
                              " +0000", committer: "" };
           } };
}
const k1 = fakeKeeper("k1"), k2 = fakeKeeper("k2");
const t1 = dag.commitTs(k1, SHA1);
ok(t1 === ron.of(1700000000 * 1000), "commitTs still returns the author ron60 ts");
let same = true;
for (let i = 0; i < 8; i++) if (dag.commitTs(k1, SHA1) !== t1) same = false;
ok(same, "…and the same ts on every re-ask");
ok(k1.n === 1, "LOG-005: commitTs parses (k1,SHA1) ONCE, not per call (" + k1.n + ")");
const t2 = dag.commitTs(k1, SHA2);
ok(t2 !== t1 && k1.n === 2, "a DIFFERENT sha is its own parse (" + k1.n + ")");
ok(dag.commitTs(k2, SHA1) === t1 && k2.n === 1,
   "a DIFFERENT keeper does not read k1's memo (" + k2.n + ")");

io.log(fails === 0 ? "PASS" : ("FAILED " + fails));
if (fails) throw "LOG005FAIL";
