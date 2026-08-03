//  test/todo/pathreuse/check.js — TODO-001: NO PATH IS PROBED TWICE.
//
//  The board render used to re-discover every page it had ALREADY been handed:
//  listTopic got the exact entry name from io.readdir and then threw it away,
//  re-deriving the file through pageFile's 6-candidate stat ladder; and the
//  work view re-ran boardDir() + pageFile() twice per wt row ([?] link then
//  [post] title).  This case COUNTS the io ops (stat/lstat/open) of the two
//  render paths over a planted fixture board and pins the reduced cost.
//
//  RED before the fix (fixture: 6 topics × (20 thin + 2 fat)):
//    listTopics  168 stat / 132 lstat+open   |  work rows  48 stat / 24 lstat+open
//  GREEN after: a thin `KEY.<ext>` entry NAMES its page (zero stats), a fat
//  `KEY/` probes README.<ext> only, and the work rows share ONE board lookup
//  plus ONE page probe per key.
"use strict";

const { eq, ok } = require("../../lib/assert.js");
//  DIS-054 isolated-clone require: derive the be/ code dir from this script's
//  own path (`<be>/test/todo/pathreuse/check.js` → `<be>`).
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const todo = _req("views/todo/todo.js");
const work = _req("views/work/work.js");

//  --- the fixture board -------------------------------------------------------
const TMP = io.getenv("TMP") || "/tmp";
const root = TMP + "/todo001-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
function mkdirp(p) {
  let acc = "";
  for (const s of p.split("/")) { if (s === "") { acc = ""; continue; } acc += "/" + s;
    try { io.mkdir(acc); } catch (e) {} }
}
function plant(abs, body) {
  mkdirp(abs.slice(0, abs.lastIndexOf("/")));
  const u = utf8.Encode(body);
  const b = io.buf(u.length + 8); b.feed(u);
  const fd = io.open(abs, "c"); io.writeAll(fd, b); io.close(fd);
}
function num(n) { return (n < 10 ? "00" : n < 100 ? "0" : "") + n; }

const BOARD = root + "/todo";
const TOPICS = ["TOPA", "TOPB", "TOPC", "TOPD", "TOPE", "TOPF"];
const THIN = 20, FAT = 2;
for (const t of TOPICS) {
  plant(BOARD + "/" + t + "/README.mkd", "#   " + t + " — landing page, never an index\n");
  for (let i = 1; i <= THIN; i++)
    plant(BOARD + "/" + t + "/" + t + "-" + num(i) + ".mkd",
          "#   " + t + "-" + num(i) + ": thin fixture ticket\n\nbody\n");
  for (let i = 1; i <= FAT; i++)
    plant(BOARD + "/" + t + "/" + t + "-" + num(100 + i) + "/README.mkd",
          "#   " + t + "-" + num(100 + i) + ": fat fixture ticket\n\nbody\n");
}
plant(BOARD + "/done/TOPA-999.mkd", "#   TOPA-999: parked, never lists\n");

//  --- the io-op counter (test/statusfast.js model) ----------------------------
const realStat = io.stat, realLstat = io.lstat, realOpen = io.open;
let stats = 0, lstats = 0, opens = 0;
function counted(fn) {
  stats = lstats = opens = 0;
  io.stat  = function () { stats++;  return realStat.apply(io, arguments); };
  io.lstat = function () { lstats++; return realLstat.apply(io, arguments); };
  io.open  = function () { opens++;  return realOpen.apply(io, arguments); };
  try { return fn(); }
  finally { io.stat = realStat; io.lstat = realLstat; io.open = realOpen; }
}

//  --- 1. the board listing ----------------------------------------------------
const groups = counted(function () { return todo.listTopics(BOARD); });
eq(groups.length, TOPICS.length, "1: every topic lists");
eq(groups[0].tickets.length, THIN + FAT, "1: every ticket of a topic lists");
eq(groups[0].tickets[0].key, TOPICS[0] + "-001", "1: numeric sort holds");
eq(groups[0].tickets[THIN + FAT - 1].key, TOPICS[0] + "-102", "1: fat tickets sort last");
ok(groups[0].tickets[0].title.indexOf("thin fixture ticket") > 0, "1: titles still read");
//  A thin page costs ZERO stats; only a fat `KEY/` probes its README.<ext>.
const listStat = stats, listRead = lstats + opens;
eq(listStat, TOPICS.length * FAT, "1: stat calls = one README probe per FAT ticket only");
eq(listRead, TOPICS.length * (THIN + FAT) * 2, "1: one lstat+open per page title read");

//  --- 2. the work view's wt rows ----------------------------------------------
//  boardDir() reads the ambient `be`; the wt rows are the REAL emitRows path.
globalThis.be = globalThis.be || {};
be.todoRoot = function () { return BOARD; };
be.now = 0n;
const ROWS = 12;
const rows = [];
for (let i = 1; i <= ROWS; i++)
  rows.push({ rails: "", wt: { key: "TOPB-" + num(i), sha: "0".repeat(40), ts: 0n,
                               subject: "s", counts: null, node: null, mark: "" } });
const fed = [];
const sink = { feed: function (b, body, toks) { fed.push({ body: body, toks: toks }); } };
counted(function () { work.emitRows(sink, rows, true); });
eq(fed.length, 1, "2: one hunk fed");
const txt = utf8.Decode(fed[0].body);
ok(txt.indexOf("[?]") >= 0, "2: the ticket [?] button still mints");
ok(txt.indexOf("[post]") >= 0, "2: the [post] button still mints (title found)");
//  ONE board lookup for the whole run + ONE page probe/title read per key.
eq(stats, 1 + ROWS, "2: stat calls = one boardDir + one pageFile per wt key");
eq(lstats + opens, ROWS * 2, "2: one lstat+open per wt key title read");

io.log("test/todo/pathreuse OK (list " + listStat + " stat/" + listRead +
       " read, work " + stats + " stat/" + (lstats + opens) + " read)\n");
