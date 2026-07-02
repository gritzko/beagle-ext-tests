//  GIT-016 test/relate/verdict — shared/relate.js verdict(keeper,cur,tip,ix?)
//  yields all five rel values (eq/ahead/behind/diverged/unrelated) over a local
//  keeper DAG + an in-memory remote wh128 index of commit->parent hashlet edges.
"use strict";

const { eq, ok } = require("../../lib/assert.js");
const relate = require("../../../shared/relate.js");
const store  = require("../../../shared/store.js");
const sha    = require("../../../shared/util/sha.js");

const TMP = io.getenv("TMP") || "/tmp";
const dir = TMP + "/git016-verdict-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
const proj = "p";
const shard = dir + "/.be/" + proj;
io.mkdir(dir); io.mkdir(dir + "/.be"); io.mkdir(shard);

const TREE = sha.frameSha("tree", new Uint8Array(0));
function body(parents, epoch, msg) {
  let s = "tree " + TREE + "\n";
  for (const p of parents) s += "parent " + p + "\n";
  s += "author A <a@e.st> " + epoch + " +0000\n";
  s += "committer A <a@e.st> " + epoch + " +0000\n\n" + msg + "\n";
  return utf8.Encode(s);
}
const E = 1700000000;
function shaOf(b) { return sha.frameSha("commit", b); }

//  --- DAG: a local trunk C0<-C1<-C2 + a remote branch off C0 (R1<-R2) and a
//  DISJOINT remote history (U1<-U2, root U0 unrelated to C0). ----------------
const bC0 = body([],   E + 100, "C0 base");        const C0 = shaOf(bC0);
const bC1 = body([C0], E + 200, "C1");             const C1 = shaOf(bC1);
const bC2 = body([C1], E + 300, "C2 local tip");   const C2 = shaOf(bC2);
//  Remote branch sharing base C0 -> diverged when both non-empty.
const bR1 = body([C0], E + 250, "R1 remote");      const R1 = shaOf(bR1);
const bR2 = body([R1], E + 350, "R2 remote tip");  const R2 = shaOf(bR2);
//  Disjoint remote history (no shared ancestor with C*) -> unrelated.
const bU0 = body([],   E + 400, "U0 alien root");  const U0 = shaOf(bU0);
const bU1 = body([U0], E + 450, "U1 alien");       const U1 = shaOf(bU1);

//  Local pack holds only C0/C1/C2; the remote commits live in the index only.
const pk = git.pack.mmap(shard + "/0000000001.keeper", "c", 1 << 16);
pk.header();
for (const b of [bC0, bC1, bC2]) pk.feed("commit", b);
pk.finish();
const k = store.open(dir, proj);

//  Remote wh128 index: commit->parent hashlet edges (WHIFFKeyPack(T_COMMIT,h60)).
const T_COMMIT = 1;
function h60(s) { return sha.hashlet60FromBytes(hex.decode(s)); }
function keyFor(h) { return (h << 4n) | BigInt(T_COMMIT); }
function mkIx(edges) {
  const ix = abc.index("wh128", { mem: 1 << 16 });
  for (const e of edges) ix.put(keyFor(h60(e[0])), h60(e[1]));
  ix.flush();
  return ix;
}
const divIx  = mkIx([[R2, R1], [R1, C0]]);   // R2<-R1<-C0 (shared base C0)
const unrIx  = mkIx([[U1, U0]]);             // U1<-U0 (no shared base)

//  --- eq: cur === tip ----------------------------------------------------
eq(relate.verdict(k, C2, C2).rel, "eq", "eq: cur === tip");

//  --- ahead: cur descends tip (behind empty) -----------------------------
//  cur=C2, tip=C0 (a local ancestor) -> only local commits ahead, none behind.
const vAhead = relate.verdict(k, C2, C0);
eq(vAhead.rel, "ahead", "ahead: cur descends tip");
eq(vAhead.behind.length, 0, "ahead: behind list empty");
ok(vAhead.ahead.length > 0, "ahead: ahead list non-empty");

//  --- behind: tip descends cur (ahead empty) -----------------------------
//  cur=C0, tip=C2 -> nothing ahead, C1/C2 behind.
const vBehind = relate.verdict(k, C0, C2);
eq(vBehind.rel, "behind", "behind: tip descends cur");
eq(vBehind.ahead.length, 0, "behind: ahead list empty");
ok(vBehind.behind.length > 0, "behind: behind list non-empty");

//  --- diverged: both non-empty, common base C0 ---------------------------
const vDiv = relate.verdict(k, C2, R2, divIx);
eq(vDiv.rel, "diverged", "diverged: both diverge over a shared base");
ok(vDiv.ahead.length > 0 && vDiv.behind.length > 0, "diverged: both lists non-empty");

//  --- unrelated: both non-empty, NO common base --------------------------
const vUnr = relate.verdict(k, C2, U1, unrIx);
eq(vUnr.rel, "unrelated", "unrelated: disjoint histories, no common base");
ok(vUnr.ahead.length > 0 && vUnr.behind.length > 0, "unrelated: both lists non-empty");

//  cleanup
for (const f of io.readdir(shard)) { try { io.unlink(shard + "/" + f); } catch (e) {} }

io.log("relate/verdict OK\n");
