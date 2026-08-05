//  GRAF-003 test/graf/persist — the work registry must PERSIST what it walked.
//  Two registry runs over ONE shard: run 1 walks and, at its tail, lands a
//  fresh `*.graf.idx` run; run 2 then answers every pair with `stats.walks`
//  0.  RED before registry().flushAll() exists (the memtable was dropped on
//  exit, ~200 pairs << MEM_FLUSH 4096, so run 2 re-walked the DAG).
"use strict";

const { eq, ok } = require("../../lib/assert.js");
const grafmod = require("../../../shared/graf.js");
const store = require("../../../shared/store.js");
const sha = require("../../../shared/util/sha.js");
const work = require("../../../views/work/work.js");

ok(typeof work.registry === "function", "work.js exposes registry() for the test");

const TMP = io.getenv("TMP") || "/tmp";
const dir = TMP + "/graf003-persist-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
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
//  The graf/cache DAG family: a C chain, a D chain, a merge M.
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
ok(store.open(dir, proj).parseCommit(M), "fixture: M reads back");

//  Far below graf's MEM_FLUSH (4096): nothing auto-persists, so ONLY an
//  explicit tail flush can carry run 1's work over to run 2 — the bug.
const PAIRS = [
  [C2, D1], [D1, C2], [C3, D1], [C3, C2], [C1, C3],
  [M, D2], [D2, M], [M, C3], [C0, C3],
];

function runCount() {
  let n = 0;
  for (const nm of io.readdir(shard)) if (nm.endsWith(".graf.idx")) n++;
  return n;
}

//  Capture the handles the registry opens, so a run's graf `stats` is readable
//  from outside (the registry owns them; the test only borrows).
const realOpen = grafmod.open;
let opened = [];
grafmod.open = function (s, o) { const g = realOpen(s, o); opened.push(g); return g; };

function renderRun() {                        // one `jab work` render, in-process
  opened = [];
  const reg = work.registry();
  const got = [];
  try {
    for (const [a, b] of PAIRS) got.push(reg.counts(repo, a, b));
    ok(typeof reg.flushAll === "function", "registry() exposes flushAll()");
    reg.flushAll();
  } finally { reg.close(); }
  eq(opened.length, 1, "ONE graf handle per shard per run");
  return { counts: got, graf: opened[0] };
}

try {
  eq(runCount(), 0, "fixture: the shard starts with no graf run");

  //  --- run 1: cold — walks, and must LAND what it walked ------------------
  const r1 = renderRun();
  ok(r1.graf.stats.walks > 0, "run 1 walks the cold DAG");
  eq(r1.counts[0].ahead, 2, "run 1: C2 vs D1 ahead is 2");
  eq(r1.counts[0].behind, 1, "run 1: C2 vs D1 behind is 1");
  eq(r1.counts[5].ahead, 3, "run 1: M vs D2 ahead is 3");
  ok(runCount() >= 1, "run 1 landed a fresh *.graf.idx run");
  const after1 = runCount();

  //  --- run 2: warm — every pair is an index hit, ZERO walks ---------------
  const r2 = renderRun();
  eq(r2.graf.stats.walks, 0, "run 2 walks NOTHING: every pair came off the runs");
  eq(r2.graf.stats.hits, PAIRS.length, "run 2: one index hit per pair");
  for (let i = 0; i < PAIRS.length; i++) {
    eq(r2.counts[i].ahead, r1.counts[i].ahead, "run 2 ahead equals run 1's, pair " + i);
    eq(r2.counts[i].behind, r1.counts[i].behind, "run 2 behind equals run 1's, pair " + i);
  }
  //  An all-hit run has an EMPTY memtable: its tail flush must land NOTHING.
  eq(runCount(), after1, "an empty memtable lands no run");
} finally { grafmod.open = realOpen; }

//  cleanup
for (const f of io.readdir(shard)) { try { io.unlink(shard + "/" + f); } catch (e) {} }

io.log("graf/persist OK\n");
