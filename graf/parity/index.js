//  WORK-011 test/graf/parity — the work view's registry().counts() ahead/behind
//  must be GRAF-BACKED and NUMERICALLY IDENTICAL to the old keeper closure diff.
//  Two legs: (1) parity — counts() equals the dag.ancestors set-difference on
//  every fixture pair; (2) delegation — with a persisted *.graf.idx run present,
//  counts() serves from the index with ZERO keeper commit reads (the old closure
//  walk would read many).  RED before counts() delegates to graf; GREEN after.
"use strict";

const { eq, ok } = require("../../lib/assert.js");
const graf = require("../../../shared/graf.js");
const dag = require("../../../shared/dag.js");
const store = require("../../../shared/store.js");
const sha = require("../../../shared/util/sha.js");
const work = require("../../../views/work/work.js");

ok(typeof work.registry === "function", "work.js exposes registry() for the test");

const TMP = io.getenv("TMP") || "/tmp";
const dir = TMP + "/graf011-parity-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
const proj = "p";
const shard = dir + "/.be/" + proj;
io.mkdir(dir); io.mkdir(dir + "/.be"); io.mkdir(shard);

const TREE = sha.frameSha("tree", new Uint8Array(0));
function commitBody(parents, epoch, msg) {
  let s = "tree " + TREE + "\n";
  for (const p of parents) s += "parent " + p + "\n";
  s += "author A <a@e.st> " + epoch + " +0000\n";
  s += "committer A <a@e.st> " + epoch + " +0000\n\n" + msg + "\n";
  return utf8.Encode(s);
}
const E = 1700000000;
//  Same DAG family as test/graf/cache: a C chain, a D chain, a merge M.
const bC0 = commitBody([],   E + 100, "C0"); const C0 = sha.frameSha("commit", bC0);
const bC1 = commitBody([C0], E + 200, "C1"); const C1 = sha.frameSha("commit", bC1);
const bC2 = commitBody([C1], E + 300, "C2"); const C2 = sha.frameSha("commit", bC2);
const bC3 = commitBody([C2], E + 400, "C3"); const C3 = sha.frameSha("commit", bC3);
const bD1 = commitBody([C0], E + 250, "D1"); const D1 = sha.frameSha("commit", bD1);
const bD2 = commitBody([D1], E + 350, "D2"); const D2 = sha.frameSha("commit", bD2);
const bM  = commitBody([C2, D1], E + 500, "M merge"); const M = sha.frameSha("commit", bM);

const pk = git.pack.mmap(shard + "/0000000001.keeper", "c", 1 << 16);
pk.header();
for (const b of [bC0, bC1, bC2, bC3, bD1, bD2, bM]) pk.feed("commit", b);
pk.finish();

const repo = { storePath: dir, project: proj };
const k = store.open(dir, proj);

//  Reference: the EXACT pre-WORK-011 closure diff (two dag.ancestors sets).
function closureDiff(cur, tip) {
  if (cur === tip) return { ahead: 0, behind: 0 };
  const a = dag.ancestors(k, cur), b = dag.ancestors(k, tip);
  let ahead = 0, behind = 0;
  for (const s of a) if (!b.has(s)) ahead++;
  for (const s of b) if (!a.has(s)) behind++;
  return { ahead: ahead, behind: behind };
}

const PAIRS = [
  [C2, D1], [D1, C2], [C3, D1], [C3, C2], [C1, C3],
  [M, D2], [D2, M], [M, C3], [C0, C3], [C2, C2],
];

//  --- leg 1: parity — graf-backed counts() equals the closure diff ---------
const reg1 = work.registry();
for (const [a, b] of PAIRS) {
  const want = closureDiff(a, b);
  const got = reg1.counts(repo, a, b);
  ok(got, "counts() returned null for a full-sha pair");
  eq(got.ahead, want.ahead, "parity ahead " + a.slice(0, 4) + " vs " + b.slice(0, 4));
  eq(got.behind, want.behind, "parity behind " + a.slice(0, 4) + " vs " + b.slice(0, 4));
}
//  A couple of pinned sanity numbers so a silently-wrong reference can't pass.
eq(reg1.counts(repo, C2, D1).ahead, 2, "C2 vs D1 ahead is 2");
eq(reg1.counts(repo, C2, D1).behind, 1, "C2 vs D1 behind is 1");
eq(reg1.counts(repo, M, D2).ahead, 3, "M vs D2 ahead is 3");

//  --- leg 2: delegation — a persisted *.graf.idx serves counts() walk-free --
//  Pre-build + flush a graf run for every pair, so each is a direct index hit.
const pre = graf.open(shard);
for (const [a, b] of PAIRS) pre.aheadBehind(k, a, b);
pre.flush();
let runs = 0;
for (const nm of io.readdir(shard)) if (nm.endsWith(".graf.idx")) runs++;
ok(runs >= 1, "flush landed a *.graf.idx run for the delegation leg");

//  A store.open spy that counts every keeper commit read the registry can make;
//  the REAL registry opens its keeper through store.open, so it gets the spy.
let calls = 0;
const realOpen = store.open;
store.open = function (a, b) {
  const kk = realOpen(a, b);
  const s = Object.create(kk);
  s.commitParents = function (x) { calls++; return kk.commitParents(x); };
  s.parseCommit = function (x) { calls++; return kk.parseCommit(x); };
  return s;
};
try {
  const reg2 = work.registry();
  for (const [a, b] of PAIRS) {
    const want = closureDiff(a, b);
    const got = reg2.counts(repo, a, b);
    eq(got.ahead, want.ahead, "index-hit ahead " + a.slice(0, 4) + " vs " + b.slice(0, 4));
    eq(got.behind, want.behind, "index-hit behind " + a.slice(0, 4) + " vs " + b.slice(0, 4));
  }
  eq(calls, 0, "graf-backed counts() served from the index with ZERO keeper reads");
} finally { store.open = realOpen; }

//  cleanup
for (const f of io.readdir(shard)) { try { io.unlink(shard + "/" + f); } catch (e) {} }

io.log("graf/parity OK\n");
