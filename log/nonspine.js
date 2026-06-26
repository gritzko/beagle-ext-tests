//  test/log/nonspine.js — LOG-001 repro: `jab log` (be/views/log/log.js)
//  must follow non-spine (merge 2nd+) parents and render them GREY.
//
//  A `jab log` that walks ONLY the first-parent spine drops a commit merged
//  in as a 2nd parent even though it is fully reachable.  This builds a
//  hermetic merge DAG (a merge tip M with parents [mainline C2, side C1]),
//  drives log.js's branchHistory, and asserts:
//    RED  (pre-fix): C1 (the 2nd parent) is OMITTED from the listing.
//    GREEN (post-fix): C1 appears, flagged non-spine, and its row toks are
//                      tagged TAG_Q (grey) so the binding's .color paints it
//                      from dog/THEME — JS re-rolls no SGR.
//  The spine commits (M, C2, C0) stay on-spine (not grey).  Bound check: a
//  `#N` cap slices the COMBINED listing.

"use strict";

const { eq, ok } = require("../lib/assert.js");
const store = require("shared/store.js");
const log = require("views/log/log.js");
const sha = require("shared/util/sha.js");

const TMP = io.getenv("TMP") || "/tmp";
const dir = TMP + "/log001-nonspine-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
const proj = "p";
const shard = dir + "/.be/" + proj;
io.mkdir(dir); io.mkdir(dir + "/.be"); io.mkdir(shard);

//  --- build the merge DAG into one keeper pack ---------------------------
//  A git commit body: tree + parent* + author/committer + blank + message.
//  Distinct epochs so commitTs orders them and mainlineParent (argmax ts)
//  picks C2 over C1 at the merge.
const TREE = sha.frameSha("tree", new Uint8Array(0));   // the empty tree sha
function commitBody(parents, epoch, msg) {
  let s = "tree " + TREE + "\n";
  for (const p of parents) s += "parent " + p + "\n";
  s += "author A <a@e.st> " + epoch + " +0000\n";
  s += "committer A <a@e.st> " + epoch + " +0000\n\n";
  s += msg + "\n";
  return utf8.Encode(s);
}

const pk = git.pack.mmap(shard + "/0000000001.keeper", "c", 1 << 16);
pk.header();
function commit(parents, epoch, msg) {
  const body = commitBody(parents, epoch, msg);
  pk.feed("commit", body);
  return sha.frameSha("commit", body);
}
//  Realistic epochs (~2024): ron60 (commitTs) can't encode 1970-era tiny
//  timestamps, so the ts-order key needs real seconds-since-epoch values.
const E = 1700000000;
const C0 = commit([],        E + 100, "C0 base");
const C1 = commit([C0],      E + 200, "C1 side (off-spine 2nd parent)");
const C2 = commit([C0],      E + 300, "C2 mainline");
const M  = commit([C2, C1],  E + 400, "M merge");   // parents: [mainline, side]
pk.finish();

const k = store.open(dir, proj);
ok(k.parseCommit(M), "fixture: merge tip M reads back as a commit");
eq(k.commitParents(M).length, 2, "fixture: M has two parents");

//  --- the walk ----------------------------------------------------------
const rows = log.branchHistory(k, M, 0);
const shasIn = rows.map(function (r) { return r.sha; });
function row(s) { for (const r of rows) if (r.sha === s) return r; return null; }

//  The spine (first-parent line): M, C2, C0 — all present, none grey.
ok(shasIn.indexOf(M)  >= 0, "M (tip) present");
ok(shasIn.indexOf(C2) >= 0, "C2 (mainline) present");
ok(shasIn.indexOf(C0) >= 0, "C0 (base) present");
eq(row(M).nonspine,  false, "M is on-spine");
eq(row(C2).nonspine, false, "C2 is on-spine");
eq(row(C0).nonspine, false, "C0 is on-spine");

//  THE REPRO: C1 (the merge's 2nd parent) must appear, flagged non-spine.
//  Pre-fix (first-parent-only walk) this row is ABSENT → red here.
ok(shasIn.indexOf(C1) >= 0, "LOG-001: C1 (merge 2nd parent) appears in the log");
eq(row(C1).nonspine, true, "LOG-001: C1 flagged non-spine (grey)");

//  Newest-first ordering by commit ts: M(4000) C2(3000) C1(2000) C0(1000).
eq(shasIn.join(","), [M, C2, C1, C0].join(","), "rows are time-ordered newest-first");

//  --- grey toks: the non-spine row carries TAG_Q over its visible span ----
//  appendRow tags a non-spine row entirely TAG_Q (the binding paints it grey
//  from dog/THEME); a spine row uses the per-column palette (never TAG_Q).
function rowTags(s, nonspine) {
  const textParts = [], spans = [];
  log.appendRow(s, k, textParts, spans, 0, nonspine);
  return spans.map(function (sp) { return sp[0]; });   // tag indices
}
const greyTags = rowTags(C1, true);
ok(greyTags.indexOf(log.TAG_Q) >= 0, "LOG-001: non-spine row carries TAG_Q (grey)");
//  A spine row never uses TAG_Q.
const spineTags = rowTags(C2, false);
eq(spineTags.indexOf(log.TAG_Q), -1, "spine row carries NO grey tag");

//  --- bound: `#N` caps the COMBINED listing (spine + non-spine) ----------
const capped = log.branchHistory(k, M, 2);
eq(capped.length, 2, "LOG-001: #N caps the combined listing");
//  The two newest survive (M, C2).
eq(capped.map(function (r) { return r.sha; }).join(","), [M, C2].join(","),
   "the cap keeps the two newest commits");

//  cleanup
for (const f of io.readdir(shard)) { try { io.unlink(shard + "/" + f); } catch (e) {} }

io.log("log/nonspine.js OK\n");
