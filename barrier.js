//  JSQUE-006: core/barrier.js — the JOIN primitive (boundary marker +
//  back-scan fold).  Repro/spec test, run with $JAB FROM INSIDE the
//  JSQUE-006 worktree (cwd = worktree); the worktree code is loaded
//  cwd-rooted so the seekBack-bearing (JSQUE-003) lib/ulog.js + the new
//  core/barrier.js are exercised, NOT the journal-root be/ shard (which
//  has neither).  Asserts: (a) the fold folds EXACTLY (marker, here);
//  (b) a chained/nested barrier (a fold's result feeds an outer fold);
//  (c) re-reading the same range is idempotent (same aggregate).
"use strict";

const { eq, ok } = require("./lib/assert.js");
const ROOT = io.cwd();                       // the JSQUE-006 worktree root
const ulog = require(ROOT + "/lib/ulog.js");
const barrier = require(ROOT + "/core/barrier.js");

const TMP = io.getenv("TMP") || "/tmp";
const dir = TMP + "/jsque006-barrier-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
io.mkdir(dir);

function rowsOf(p) {
  const out = [];
  ulog.each(p, function (log) {
    out.push({ offset: log.offset, verb: log.verb, uri: log.uri });
  });
  return out;
}

//  A fold fn that concatenates the leaf URIs (a stand-in for the POST
//  build-tree fold): each leaf contributes its uri; the result is the
//  joined aggregate (a "tree sha" analogue — deterministic over the range).
function joinFold(acc, row) { acc.push(row.verb + ":" + row.uri); return acc; }

//  ----- (a) range exactness: fold EXACTLY (marker, here) -----------------
//  Two marker/leaf/fold groups in one queue; the SECOND fold must absorb
//  only the leaves after the SECOND marker, never the first group's.
const p = dir + "/queue";
barrier.emit(p, "mark", "boundary/1",
  [{ verb: "add", uri: "a.c#sha1" }, { verb: "unlink", uri: "b.c" }],
  "fold", "result/1");
barrier.emit(p, "mark", "boundary/2",
  [{ verb: "add", uri: "c.c#sha3" }],
  "fold", "result/2");

const all = rowsOf(p);
//  Locate the two fold rows by verb.
const folds = all.filter((r) => r.verb === "fold");
eq(folds.length, 2, "a: two fold rows present");

//  Fold the FIRST group (its fold row is folds[0]); range = its two leaves.
const r1 = barrier.fold(p, folds[0].offset, "mark", joinFold, []);
eq(r1.acc.length, 2, "a: first fold absorbs exactly its 2 leaves");
eq(r1.acc[0], "add:a.c#sha1", "a: first leaf");
eq(r1.acc[1], "unlink:b.c", "a: second leaf");
eq(r1.marker.uri, "boundary/1", "a: first fold's marker is boundary/1");

//  Fold the SECOND group; range = the single leaf after boundary/2 ONLY.
const r2 = barrier.fold(p, folds[1].offset, "mark", joinFold, []);
eq(r2.acc.length, 1, "a: second fold absorbs exactly its 1 leaf (not the first group)");
eq(r2.acc[0], "add:c.c#sha3", "a: second group leaf");
eq(r2.marker.uri, "boundary/2", "a: second fold's marker is boundary/2");

//  ----- (c) re-read idempotency: same range -> same aggregate ------------
//  Results are durable (the fold re-reads the rows; nothing held in memory),
//  so a replay over the SAME [marker, here) yields the SAME aggregate.
const r2b = barrier.fold(p, folds[1].offset, "mark", joinFold, []);
eq(r2b.acc.length, r2.acc.length, "c: replay same leaf count");
eq(r2b.acc[0], r2.acc[0], "c: replay same aggregate");

//  ----- (b) nested / chained barrier -------------------------------------
//  A subtree's fold writes its result row; the OUTER fold folds those
//  result rows (blobs -> subtree -> root, the POST build-tree chain).  We
//  emit two inner groups whose fold rows are themselves leaves of an outer
//  group, then run the outer fold over the inner results.
const np = dir + "/nested";
//  inner group A: two blobs -> one subtree-result row.
barrier.emit(np, "submark", "sub/a",
  [{ verb: "blob", uri: "a/x#s1" }, { verb: "blob", uri: "a/y#s2" }],
  "subtree", "tree/a#TA");
//  inner group B: one blob -> one subtree-result row.
barrier.emit(np, "submark", "sub/b",
  [{ verb: "blob", uri: "b/z#s3" }],
  "subtree", "tree/b#TB");
//  outer group: a root marker, then the inner RESULT rows replayed as the
//  outer leaves, then the root fold.  (Post-order: inner results precede
//  the root fold row.)
const innerAll = rowsOf(np);
const subtrees = innerAll.filter((r) => r.verb === "subtree");
eq(subtrees.length, 2, "b: two inner subtree-result rows");
barrier.emit(np, "rootmark", "root",
  subtrees.map((r) => ({ verb: r.verb, uri: r.uri })),
  "roottree", "tree/root#RT");

const npAll = rowsOf(np);
const roots = npAll.filter((r) => r.verb === "roottree");
eq(roots.length, 1, "b: one root fold row");
//  The outer fold absorbs EXACTLY the two inner subtree-result rows.
const ro = barrier.fold(np, roots[0].offset, "rootmark", joinFold, []);
eq(ro.acc.length, 2, "b: root fold absorbs the 2 inner subtree results");
eq(ro.acc[0], "subtree:tree/a#TA", "b: first inner subtree result");
eq(ro.acc[1], "subtree:tree/b#TB", "b: second inner subtree result");

//  And the inner folds still resolve their OWN ranges independently
//  (chaining doesn't disturb a nested fold's boundary).
const innerFold = barrier.fold(np, subtrees[0].offset, "submark", joinFold, []);
eq(innerFold.acc.length, 2, "b: inner-A fold still absorbs its 2 blobs");
eq(innerFold.marker.uri, "sub/a", "b: inner-A marker is sub/a");

//  ----- empty-range fold: marker immediately precedes the fold row -------
const ep = dir + "/empty";
barrier.emit(ep, "mark", "b0", [], "fold", "result/empty");
const eAll = rowsOf(ep);
const eFold = eAll.filter((r) => r.verb === "fold")[0];
const re = barrier.fold(ep, eFold.offset, "mark", joinFold, []);
eq(re.acc.length, 0, "empty: a marker-then-fold folds zero leaves");
ok(re.marker && re.marker.uri === "b0", "empty: marker still resolved");

//  cleanup
for (const f of io.readdir(dir)) { try { io.unlink(dir + "/" + f); } catch (e) {} }

io.log("barrier.js OK\n");
