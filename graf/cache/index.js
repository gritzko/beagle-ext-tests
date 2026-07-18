//  GRAF-001 test/graf/cache — shared/graf.js: cached ahead/behind pair counts.
//  A pair walked once must be an INDEX HIT on the second ask (keeper-call spy
//  = walk-free); covers recurrence, merge paint, saturation, truncation
//  no-cache, and run persistence (reopen the shard, still a hit).
"use strict";

const { eq, ok } = require("../../lib/assert.js");
const graf = require("../../../shared/graf.js");
const sha = require("../../../shared/util/sha.js");

const TMP = io.getenv("TMP") || "/tmp";
const dir = TMP + "/graf001-cache-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
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

//  Fixture DAG (all epochs distinct, children newer than parents):
//      C0 <- C1 <- C2 <- C3         (the A chain)
//      C0 <- D1 <- D2               (the B chain)
//      M  = merge(C2, D1)
//      Xm (NOT in the pack) <- Xt   (the truncation probe)
const bC0 = commitBody([],   E + 100, "C0"); const C0 = sha.frameSha("commit", bC0);
const bC1 = commitBody([C0], E + 200, "C1"); const C1 = sha.frameSha("commit", bC1);
const bC2 = commitBody([C1], E + 300, "C2"); const C2 = sha.frameSha("commit", bC2);
const bC3 = commitBody([C2], E + 400, "C3"); const C3 = sha.frameSha("commit", bC3);
const bD1 = commitBody([C0], E + 250, "D1"); const D1 = sha.frameSha("commit", bD1);
const bD2 = commitBody([D1], E + 350, "D2"); const D2 = sha.frameSha("commit", bD2);
const bM  = commitBody([C2, D1], E + 500, "M merge"); const M = sha.frameSha("commit", bM);
const bXm = commitBody([C0], E + 150, "Xm missing"); const Xm = sha.frameSha("commit", bXm);
const bXt = commitBody([Xm], E + 600, "Xt tip");     const Xt = sha.frameSha("commit", bXt);

const pk = git.pack.mmap(shard + "/0000000001.keeper", "c", 1 << 16);
pk.header();
for (const b of [bC0, bC1, bC2, bC3, bD1, bD2, bM, bXt]) pk.feed("commit", b);
pk.finish();

const store = require("../../../shared/store.js");
const k = store.open(dir, proj);
ok(k.parseCommit(M), "fixture: M reads back");
ok(k.getObject(Xm) === undefined, "fixture: Xm is NOT in the store");

//  Keeper-call spy: counts every commit read the walks can make.
function spy() {
  const s = { calls: 0, store: Object.create(k) };
  s.store.commitParents = function (x) { s.calls++; return k.commitParents(x); };
  s.store.parseCommit = function (x) { s.calls++; return k.parseCommit(x); };
  return s;
}

//  --- linear divergence: walk once, then index-hit (walk-free) -----------
const g = graf.open(shard);
const s1 = spy();
let r = g.aheadBehind(s1.store, C2, D1);
eq(r.ahead, 2, "C2 vs D1 ahead {C1,C2}");
eq(r.behind, 1, "C2 vs D1 behind {D1}");
ok(s1.calls > 0, "first ask walks");
const c1 = s1.calls;
r = g.aheadBehind(s1.store, C2, D1);
eq(r.ahead, 2, "hit: ahead equal");
eq(r.behind, 1, "hit: behind equal");
eq(s1.calls, c1, "second ask is WALK-FREE");
r = g.aheadBehind(s1.store, D1, C2);
eq(r.ahead, 1, "mirror ahead");
eq(r.behind, 2, "mirror behind");
eq(s1.calls, c1, "mirror orientation is walk-free too");

//  --- recurrence: single-parent child of a cached pair -------------------
const c2 = s1.calls;
r = g.aheadBehind(s1.store, C3, D1);
eq(r.ahead, 3, "C3 vs D1 ahead {C1,C2,C3}");
eq(r.behind, 1, "C3 vs D1 behind {D1}");
eq(s1.calls, c2 + 1, "recurrence: ONE parent probe, no full walk");
const c3 = s1.calls;
r = g.aheadBehind(s1.store, C3, D1);
eq(s1.calls, c3, "recurrence result cached");

//  --- merge commit: the two-tip paint-BFS path ---------------------------
const c4 = s1.calls;
r = g.aheadBehind(s1.store, M, D2);
eq(r.ahead, 3, "M vs D2 ahead {M,C2,C1}");
eq(r.behind, 1, "M vs D2 behind {D2}");
ok(s1.calls > c4, "merge ask walks (paint)");
const c5 = s1.calls;
r = g.aheadBehind(s1.store, M, D2);
eq(r.ahead, 3, "merge hit: ahead equal");
eq(r.behind, 1, "merge hit: behind equal");
eq(s1.calls, c5, "merge pair cached, walk-free");

//  --- saturation: counts clamp at the cap and ARE cacheable --------------
const g2 = graf.open(shard, { satCap: 2 });   // test hook; prod cap = 0xFFFFF
const s2 = spy();
r = g2.aheadBehind(s2.store, C3, D1);
eq(r.ahead, 2, "saturated: ahead clamps at cap (real 3)");
eq(r.behind, 1, "saturated: behind exact");
ok(s2.calls > 0, "saturation ask walked");
const c6 = s2.calls;
r = g2.aheadBehind(s2.store, C3, D1);
eq(r.ahead, 2, "saturated pair IS cached: ahead");
eq(r.behind, 1, "saturated pair IS cached: behind");
eq(s2.calls, c6, "saturated pair IS cached: walk-free");

//  --- truncated walk (missing ancestor) must NOT be cached ---------------
const s3 = spy();
r = g.aheadBehind(s3.store, Xt, D1);
const t1 = { ahead: r.ahead, behind: r.behind };
const c7 = s3.calls;
ok(c7 > 0, "truncated ask walks");
r = g.aheadBehind(s3.store, Xt, D1);
ok(s3.calls > c7, "truncated result NOT cached: second ask walks again");
eq(r.ahead, t1.ahead, "truncated: stable ahead");
eq(r.behind, t1.behind, "truncated: stable behind");

//  --- persistence: flush -> a run file -> reopen -> still a hit ----------
g.flush();
let runs = [];
for (const nm of io.readdir(shard)) if (nm.endsWith(".graf.idx")) runs.push(nm);
ok(runs.length >= 1, "flush landed a *.graf.idx run");
const g3 = graf.open(shard);
const s4 = spy();
r = g3.aheadBehind(s4.store, C2, D1);
eq(r.ahead, 2, "reopen: ahead from the run");
eq(r.behind, 1, "reopen: behind from the run");
eq(s4.calls, 0, "reopen: pure index hit, zero keeper calls");
r = g3.aheadBehind(s4.store, D2, M);
eq(r.ahead, 1, "reopen mirror: ahead");
eq(r.behind, 3, "reopen mirror: behind");
eq(s4.calls, 0, "reopen mirror: zero keeper calls");

//  cleanup
for (const f of io.readdir(shard)) { try { io.unlink(shard + "/" + f); } catch (e) {} }

io.log("graf/cache OK\n");
