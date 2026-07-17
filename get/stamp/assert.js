//  GET-049 assert: get must stamp every checkout-written file to the get row's
//  ts (the STATUS-011 stamp-set invariant) — status then confirms it clean
//  with ZERO per-file content reads (io.open, the statusfast.js hook).
//  Modes:  assert.js <wt> clone                      every tracked file's
//          mtime == the LAST sha-carrying get row ts;
//          assert.js <wt> update <written...> -- <untouched...>   written
//          files == the LAST row ts, untouched keep the CLONE row's stamp.
//  Both modes then classify (warm-up + counted) and demand 0 opens, 0 rows.
"use strict";
//  DIS-054 isolated-clone require (statusfast.js style): derive the code dir
//  from this script's own path (`<be>/test/get/stamp/assert.js` → `<be>`).
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const classify = _req("shared/classify.js");
const wtlog = _req("shared/wtlog.js");
const store = _req("shared/store.js");
const discover = _req("core/discover.js");

const wt = process.argv[2];
const mode = process.argv[3];

const info = discover.treeAt(wt);
const wtl = wtlog.open(info);
const k = store.open(info.storePath, info.project);

//  The sha-carrying get rows (the tip records; the row-0 store redirect and
//  con/put rows carry no 40-hex fragment).  first = clone stamp, last = newest.
const getRows = [];
for (const r of wtl.rows)
  if (r.verb === "get" && /^[0-9a-f]{40}$/.test(r.uri.fragment || ""))
    getRows.push(r);
if (!getRows.length) throw "getstamp: no get tip row in " + info.bePath;
const first = getRows[0], last = getRows[getRows.length - 1];

let bad = 0;
function expect(rel, wantTs, label) {
  let m;
  try { m = io.lstat(wt + "/" + rel).mtime; }
  catch (e) { io.log("NOFILE " + label + " " + rel + "\n"); bad++; return; }
  if (ron.encode(m) !== ron.encode(wantTs)) {
    io.log("MISMATCH " + label + " " + rel + " mtime=" + ron.encode(m) +
           " want=" + ron.encode(wantTs) + "\n");
    bad++;
  }
}

if (mode === "clone") {
  const tree = k.commitTree(last.uri.fragment);
  if (!tree) throw "getstamp: tip has no tree";
  k.readTreeRecursive(tree, function (l) {
    if (l.kind === "s" || l.kind === "l") return;   // gitlinks/links unstamped
    expect(l.path, last.ts, "clone");
  });
} else if (mode === "update") {
  let cur = "written";
  for (let i = 4; i < process.argv.length; i++) {
    const a = process.argv[i];
    if (a === "--") { cur = "untouched"; continue; }
    expect(a, cur === "written" ? last.ts : first.ts, cur);
  }
} else throw "getstamp: unknown mode " + mode;
if (bad) throw "getstamp: " + bad + " mtime mismatch(es)";

//  Status fast path: a warm-up pass pays any one-off store/index reads, then
//  the counted pass must do ZERO io.open content reads (all stamps hit) and
//  emit no rows (clean wt).  classify is read-only (DIS-023: no re-stamping).
classify.classify(info, wtl, k);
const realOpen = io.open;
let opens = 0;
io.open = function () { opens++; return realOpen.apply(io, arguments); };
let res;
try { res = classify.classify(info, wtl, k); } finally { io.open = realOpen; }
if (res.rows.length !== 0)
  throw "getstamp: status not clean: " +
        res.rows.map(function (r) { return r.bucket + " " + r.path; }).join(", ");
if (opens !== 0)
  throw "getstamp: " + opens + " content read(s) on a fully stamped wt";
