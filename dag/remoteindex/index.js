//  GIT-016 test/dag/remoteindex — shared/dag.js over an OPTIONAL remote wh128
//  index: remote-only ancestry is invisible WITHOUT the index and crossable WITH
//  it (isAncestor / aheadBehind span local keeper + in-memory remote edges).
"use strict";

const { eq, ok } = require("../../lib/assert.js");
const dag = require("../../../shared/dag.js");
const sha = require("../../../shared/util/sha.js");

const TMP = io.getenv("TMP") || "/tmp";
const dir = TMP + "/git016-remoteindex-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
const proj = "p";
const shard = dir + "/.be/" + proj;
io.mkdir(dir); io.mkdir(dir + "/.be"); io.mkdir(shard);

//  GIT-016: a git commit body (tree + parent* + author/committer + msg); distinct
//  epochs so commitTs orders the ahead/behind rows newest-first.
const TREE = sha.frameSha("tree", new Uint8Array(0));
function commitBody(parents, epoch, msg) {
  let s = "tree " + TREE + "\n";
  for (const p of parents) s += "parent " + p + "\n";
  s += "author A <a@e.st> " + epoch + " +0000\n";
  s += "committer A <a@e.st> " + epoch + " +0000\n\n" + msg + "\n";
  return utf8.Encode(s);
}
const E = 1700000000;

//  --- LOCAL keeper pack: C0 <- C1 <- C2 (cur = C2) -----------------------
const bodies = {};
function mkBody(parents, epoch, msg) { const b = commitBody(parents, epoch, msg); return b; }
const bC0 = mkBody([],   E + 100, "C0 base");
const C0  = sha.frameSha("commit", bC0);
const bC1 = mkBody([C0], E + 200, "C1 local");
const C1  = sha.frameSha("commit", bC1);
const bC2 = mkBody([C1], E + 300, "C2 local tip");
const C2  = sha.frameSha("commit", bC2);
//  Remote-only commits C0 <- R1 <- R2 (tip = R2); C0 is the SHARED base.
const bR1 = mkBody([C0], E + 250, "R1 remote");
const R1  = sha.frameSha("commit", bR1);
const bR2 = mkBody([R1], E + 350, "R2 remote tip");
const R2  = sha.frameSha("commit", bR2);

//  Only the LOCAL commits (C0,C1,C2) go into the keeper pack — R1/R2 are NOT
//  local (their bodies exist only so their shas/hashlets are real & consistent).
const pk = git.pack.mmap(shard + "/0000000001.keeper", "c", 1 << 16);
pk.header();
for (const b of [bC0, bC1, bC2]) pk.feed("commit", b);
pk.finish();

const store = require("../../../shared/store.js");
const k = store.open(dir, proj);
ok(k.parseCommit(C2), "fixture: C2 reads back from the keeper pack");
ok(k.getObject(R2) === undefined, "fixture: R2 is NOT in the local keeper store");

//  --- in-memory remote wh128 index: commit->parent hashlet edges ----------
//  GIT-016: keyed by WHIFFKeyPack(T_COMMIT, hashlet60(child)); val = hashlet60
//  of a parent — the SAME shape store.js/ingest.js/head.js use.
const T_COMMIT = 1;
function h60(s) { return sha.hashlet60FromBytes(hex.decode(s)); }
function keyFor(h) { return (h << 4n) | BigInt(T_COMMIT); }
const ix = abc.index("wh128", { mem: 1 << 16 });
ix.put(keyFor(h60(R2)), h60(R1));   // R2 -> R1
ix.put(keyFor(h60(R1)), h60(C0));   // R1 -> C0 (into the shared base)
ix.flush();

//  --- WITHOUT the index: R2's remote ancestry is invisible ----------------
eq(dag.isAncestor(k, C0, R2), false, "no-index: C0 not seen as ancestor of R2");
eq(dag.isAncestor(k, R1, R2), false, "no-index: R1 not seen as ancestor of R2");

//  --- WITH the index: the remote edges are crossed ------------------------
ok(dag.isAncestor(k, C0, R2, ix), "index: C0 is an ancestor of R2");
ok(dag.isAncestor(k, R1, R2, ix), "index: R1 is an ancestor of R2");
//  Push verdict: R2 does NOT descend the local tip C2 (they diverge at C0).
eq(dag.isAncestor(k, R2, C2, ix), false, "index: R2 is NOT an ancestor of C2 (push non-FF)");

//  --- aheadBehind(C2, R2, ix): ahead={C1,C2}, behind={R2,R1}, base C0 in neither
//  ahead rows are local (full sha); behind rows are the remote tip R2 (the walk
//  root carries its sha) + the remote-only R1 (hashlet-keyed, sha unknown).
const ab = dag.aheadBehind(k, C2, R2, ix);
const aheadShas = ab.ahead.map(function (r) { return r.sha; });
//  A behind row is identified either by its full sha (the R2 root) or its
//  remote hashlet60 (R1); build one id-set spanning both shapes.
const behindIds = ab.behind.map(function (r) { return r.sha ? r.sha : String(r.hashlet); });
eq(aheadShas.indexOf(C2) >= 0, true, "ahead includes C2");
eq(aheadShas.indexOf(C1) >= 0, true, "ahead includes C1");
eq(aheadShas.indexOf(C0), -1, "ahead excludes the shared base C0");
eq(ab.ahead.length, 2, "ahead is exactly {C1,C2}");
eq(behindIds.indexOf(R2) >= 0, true, "behind includes R2 (tip, full sha)");
eq(behindIds.indexOf(String(h60(R1))) >= 0, true, "behind includes R1 (remote hashlet)");
eq(behindIds.indexOf(C0), -1, "behind excludes the shared base C0");
eq(behindIds.indexOf(String(h60(C0))), -1, "behind excludes C0 (by hashlet too)");
eq(ab.behind.length, 2, "behind is exactly {R2,R1}");

//  cleanup
for (const f of io.readdir(shard)) { try { io.unlink(shard + "/" + f); } catch (e) {} }

io.log("dag/remoteindex OK\n");
