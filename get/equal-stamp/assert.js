//  GET-059 assert: after a get, every file the get proved equal to the new
//  base carries a wtlog-stamp mtime, and the next status confirms it clean
//  with ZERO content reads (the STATUS-011 observable, same readers status.js
//  uses).  A still-dirty file must NOT be stamped into the set.
//    assert.js <wt> -clean <rel...> -dirty <rel...>
"use strict";
//  DIS-054 isolated-clone require (the stamp/assert.js twin): derive the code
//  dir from this script's own path (`<be>/test/get/equal-stamp/assert.js`).
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const classify = _req("shared/classify.js");
const wtlog    = _req("shared/wtlog.js");
const store    = _req("shared/store.js");
const discover = _req("core/discover.js");

const wt = process.argv[2];
const clean = [], dirty = [];
let cur = null;
for (let i = 3; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a === "-clean") { cur = clean; continue; }
  if (a === "-dirty") { cur = dirty; continue; }
  if (!cur) throw "equal-stamp: rel before -clean/-dirty: " + a;
  cur.push(a);
}

const info = discover.treeAt(wt);
const wtl  = wtlog.open(info);
const k    = store.open(info.storePath, info.project);

const bad = [];
function mtimeOf(rel) {
  try { return io.lstat(info.wt + "/" + rel).mtime; }
  catch (e) { bad.push("NOFILE " + rel); return null; }
}
//  1. membership: a tested-equal file's mtime IS a wtlog row ts; a dirty
//     file's mtime is NOT (a band stamp sits under the row ceiling).
for (const rel of clean) {
  const m = mtimeOf(rel);
  if (m != null && !wtl.has(m))
    bad.push("NOSTAMP " + rel + " mtime=" + ron.encode(m));
}
for (const rel of dirty) {
  const m = mtimeOf(rel);
  if (m != null && wtl.has(m))
    bad.push("FALSESTAMP " + rel + " mtime=" + ron.encode(m));
}

//  2. the status fast path: a warm-up pass pays the one-off store reads, then
//     the counted pass must open NONE of the clean files (all stamps hit).
classify.classify(info, wtl, k);
const opened = [], realOpen = io.open;
io.open = function (p) { opened.push(String(p)); return realOpen.apply(io, arguments); };
let res;
try { res = classify.classify(info, wtl, k); } finally { io.open = realOpen; }
for (const rel of clean) {
  const full = info.wt + "/" + rel;
  for (const p of opened) if (p === full) { bad.push("READ " + rel); break; }
}

//  3. the verdicts themselves: clean files emit no dirty row, the dirty
//     control still does (get must never launder real dirt into `ok`).
const rowOf = {};
for (const r of res.rows) rowOf[r.path] = r.bucket;
for (const rel of clean) if (rowOf[rel]) bad.push("DIRTY " + rowOf[rel] + " " + rel);
for (const rel of dirty) if (!rowOf[rel]) bad.push("LAUNDERED " + rel);

function w(s) { const u = utf8.Encode(s); const b = io.buf(u.length + 8); b.feed(u); io.write(1, b); }
if (bad.length) {
  w("equal-stamp FAIL " + wt + "\n" + bad.join("\n") + "\n");
  throw "equal-stamp: " + bad.length + " violation(s)";
}
w("equal-stamp ok " + wt + " (" + clean.length + " tested-equal stamped, " +
  dirty.length + " dirty unstamped, 0 reads)\n");
