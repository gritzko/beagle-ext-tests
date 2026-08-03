//  test/todo/sort/check.js — TODO-004 time-sort: the COMPARATOR itself, over
//  hand-built rows.  run.sh proves the end-to-end order through the real verb;
//  this proves the three groups and their tie-breaks without a repo, including
//  the one shape a live tree cannot be made to show on demand — a CLEAN ticket
//  the lane could not attribute within its fill budget (BRO-044: it renders
//  blank and sorts LAST, stably, and attributes on a later, deeper query).
"use strict";

//  DIS-054: derive the be/ code dir from THIS script's path (test/ingest.js model).
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const todo = _req("views/todo/todo.js");

//  `check.js --mtimes <file>…` — the fixture assertion run.sh cannot make
//  portably in shell: every named file's fs mtime is the SAME instant (the
//  fresh-clone shape, where a checkout has restamped them all).
if (process.argv[2] === "--mtimes") {
  const seen = {};
  let n = 0;
  for (let i = 3; i < process.argv.length; i++) {
    seen[String(io.stat(process.argv[i]).mtime)] = 1;
    n++;
  }
  const distinct = Object.keys(seen);
  if (n < 2 || distinct.length !== 1) {
    io.log("FAIL --mtimes: " + n + " files, " + distinct.length +
           " distinct mtimes (" + distinct.join(",") + ")\n");
    throw "todo/sort: the fixture mtimes did not tie";
  }
  io.log("todo/sort check: " + n + " files tie at mtime " + distinct[0] + "\n");
} else {

let bad = 0;
function eq(got, want, what) {
  if (got === want) return;
  io.log("FAIL " + what + ": got " + got + " want " + want + "\n");
  bad++;
}
//  rows -> the key order the comparator produces.
function order(rows) {
  return rows.slice().sort(todo.byFresh).map(function (r) { return r.key; }).join(" ");
}
const D = (key, mtime) => ({ key: key, dirty: true, mtime: BigInt(mtime) });
const C = (key, ts) => ({ key: key, dirty: false, ts: BigInt(ts) });
const U = (key) => ({ key: key, dirty: false });          // clean, unattributed

//  1. DIRTY first, freshest fs mtime first — and a dirty ticket outranks a
//     committed one whose commit time is larger than any mtime on the page.
eq(order([C("AAA-1", 9000), D("AAA-2", 10), D("AAA-3", 20)]),
   "AAA-3 AAA-2 AAA-1", "dirty first, mtime desc");

//  2. COMMITTED rows order by the introducing commit, newest first.
eq(order([C("AAA-1", 100), C("AAA-2", 300), C("AAA-3", 200)]),
   "AAA-2 AAA-3 AAA-1", "committed newest-commit first");

//  3. The FRESH-CLONE tie: every mtime identical (a checkout restamps them all),
//     so only the commit time can order the page.
eq(order([C("AAA-1", 100), C("AAA-2", 300), C("AAA-3", 200)].map(function (r) {
     r.mtime = 12345n; return r; })),
   "AAA-2 AAA-3 AAA-1", "identical mtimes, commit time decides");

//  4. UNATTRIBUTED (clean, no lane row) sorts LAST — after every dated row,
//     dirty or committed — and among themselves by code, stably.
eq(order([U("AAA-2"), C("AAA-3", 100), U("AAA-1"), D("AAA-4", 5)]),
   "AAA-4 AAA-3 AAA-1 AAA-2", "unattributed last, byCode among themselves");

//  5. Every tie falls back to byCode (topic, then ticket number) — so the
//     listing is reproducible, never readdir-ordered.
eq(order([C("BBB-2", 100), C("AAA-10", 100), C("AAA-9", 100)]),
   "AAA-9 AAA-10 BBB-2", "equal times tie-break by topic+number");
eq(order([D("BBB-1", 7), D("AAA-2", 7), D("AAA-1", 7)]),
   "AAA-1 AAA-2 BBB-1", "equal mtimes tie-break by topic+number");

//  6. NO repo to date against: nothing is dirty and nothing has a time, so
//     byFresh degrades EXACTLY to the byCode order the view had before.
const undated = [{ key: "BBB-1" }, { key: "AAA-2" }, { key: "AAA-1" }];
eq(order(undated), "AAA-1 AAA-2 BBB-1", "undated rows keep the byCode order");
eq(order(undated), undated.slice().sort(todo.byCode)
     .map(function (r) { return r.key; }).join(" "), "undated == byCode");

if (bad) { io.log("todo/sort check: " + bad + " failure(s)\n"); throw "todo/sort check failed"; }
io.log("todo/sort check: comparator OK\n");
}
