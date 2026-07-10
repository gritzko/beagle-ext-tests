//  JS-116: keeper.idx run lifecycle — the maintenance loop store.js diskIndex()
//  must run on open.  Repros pinned here:
//  (1) STALE TAIL: a `.keeper` log landed WITHOUT its idx run into a shard that
//      HAS a run leaves the new objects silently unlocatable (the TEST-003
//      quirk, PATCH-011's motive) — open must build + persist the tail run.
//  (2) RUN ACCUMULATION: runs only ever pile up; >32 on open must compact
//      (native leaves hard-cap queries at 64 — a 70-run shard cannot even be
//      ranged), collapsed sources unlinked, no `00000000`-padded names.
//  (3) AFTER-ADD: ingest.land() must keep the 1/8 size-tiered invariant.
"use strict";

const { eq, ok } = require("./lib/assert.js");
//  DIS-054: an ISOLATED ticket clone gives the test tree its OWN `.be` shard,
//  so a be-relative require resolves against THAT (code-less) shard.  Derive
//  the be/ code dir from THIS script's own path; fall back to be-relative.
const store = _req("shared/store.js");
const ingest = _req("shared/ingest.js");
const shalib = _req("shared/util/sha.js");
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}

const TMP = io.getenv("TMP") || "/tmp";
const PROJ = "p";

function freshStore(tag) {
  const dir = TMP + "/js116-" + tag + "-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
  const shard = dir + "/.be/" + PROJ;
  io.mkdir(dir); io.mkdir(dir + "/.be"); io.mkdir(shard);
  return { dir: dir, shard: shard };
}

//  Write a `NNNNNNNNNN.keeper` pack-log with one blob per text (the JS-056
//  fixture recipe) → [{ sha, body }].  NO idx run is built here.
function writeLog(shard, nm, texts) {
  const pk = git.pack.mmap(shard + "/" + nm, "c", 1 << 16);
  pk.header();
  const out = [];
  for (const t of texts) {
    const body = utf8.Encode(t);
    pk.feed("blob", body);
    out.push({ sha: shalib.frameSha("blob", body), body: body });
  }
  pk.finish();
  return out;
}

//  A minimal but REAL git packfile (wire shape: + 20-byte sha1 trailer) for
//  ingest.land() — the test/ingest.js makePack recipe.
function makePack(texts) {
  const ta = new Uint8Array(1 << 16);
  const pk = git.pack.over(ta);
  pk.header();
  const shas = [];
  for (const t of texts) {
    const body = utf8.Encode(t);
    pk.feed("blob", body, -1, null);
    shas.push(shalib.frameSha("blob", body));
  }
  pk.finish();
  const wm = Number(pk.buffer.watermark);
  const full = new Uint8Array(wm + 20);
  full.set(ta.subarray(0, wm), 0);
  full.set(sha1(ta.subarray(0, wm)), wm);
  return { pack: full, shas: shas };
}

function runNames(shard) {
  const out = [];
  for (const nm of io.readdir(shard)) if (nm.endsWith("keeper.idx")) out.push(nm);
  out.sort();
  return out;
}

function cleanup(shard) {
  for (const f of io.readdir(shard)) { try { io.unlink(shard + "/" + f); } catch (e) {} }
}

//  --- (1) stale tail: log landed without its run → open builds + persists ---
{
  const s = freshStore("stale");
  const A = writeLog(s.shard, "0000000001.keeper", ["js116 stale A0", "js116 stale A1"]);
  ingest.buildIndex(s.shard, "0000000001.keeper", 1);   // proper run, 0xF row
  eq(runNames(s.shard).length, 1, "stale: one proper run seeded");
  //  land a second log with NO idx run — the crash-between-leaves state.
  const B = writeLog(s.shard, "0000000002.keeper", ["js116 stale B0", "js116 stale B1"]);
  const before = runNames(s.shard).join(",");

  const r = store.open(s.dir, PROJ);
  const bobj = r.getObject(B[0].sha);
  ok(r._diskIndex() != null, "stale: store opened the on-disk keeper.idx runs");
  ok(bobj && bobj.type === "blob",
     "stale: unindexed log's object locatable after open (tail run built)");
  ok(runNames(s.shard).join(",") !== before,
     "stale: the tail run was PERSISTED (not the ephemeral in-RAM rebuild)");
  const aobj = r.getObject(A[1].sha);
  ok(aobj && aobj.type === "blob", "stale: older log still resolves");

  //  re-open: coverage now matches io.stat — no further run is added.
  const n = runNames(s.shard).length;
  const r2 = store.open(s.dir, PROJ);
  ok(r2.getObject(B[1].sha), "stale: re-open still resolves");
  eq(runNames(s.shard).length, n, "stale: covered shard adds NO run on re-open");
  cleanup(s.shard);
}

//  --- (2a) compact-on-open: >32 runs collapse; sources unlinked ------------
{
  const s = freshStore("pile");
  const A = writeLog(s.shard, "0000000001.keeper",
                     ["js116 pile 0", "js116 pile 1", "js116 pile 2"]);
  for (let i = 0; i < 40; i++)                     // 40 identical ron-named runs
    ingest.buildIndex(s.shard, "0000000001.keeper", 1);
  eq(runNames(s.shard).length, 40, "pile: 40 runs accumulated");

  const r = store.open(s.dir, PROJ);
  ok(r.getObject(A[2].sha), "pile: object locatable through the pile");
  const after = runNames(s.shard);
  ok(after.length <= 32, "pile: >32-run shard compacted on open (now " +
     after.length + ")");
  for (const nm of after)
    ok(!/^\d{8}\./.test(nm), "pile: no padStart(8) run name leaked: " + nm);
  for (const nm of io.readdir(s.shard))
    ok(!nm.endsWith(".tmp"), "pile: no .tmp leftover: " + nm);
  ok(r.getObject(A[0].sha), "pile: still locatable after compaction");
  cleanup(s.shard);
}

//  --- (2b) past the native 64-run cap: open must batch, not throw ----------
{
  const s = freshStore("cap");
  const A = writeLog(s.shard, "0000000001.keeper", ["js116 cap 0", "js116 cap 1"]);
  for (let i = 0; i < 70; i++)
    ingest.buildIndex(s.shard, "0000000001.keeper", 1);
  eq(runNames(s.shard).length, 70, "cap: 70 runs accumulated (past the 64 cap)");

  const r = store.open(s.dir, PROJ);
  let obj;
  try { obj = r.getObject(A[0].sha); }
  catch (e) { throw "FAIL cap: locate over an overfull shard threw: " + e; }
  ok(obj && obj.type === "blob", "cap: overfull shard opens + resolves");
  ok(runNames(s.shard).length <= 32, "cap: batched below the native cap");
  cleanup(s.shard);
}

//  --- (3) after-add: land() keeps the 1/8 invariant ------------------------
{
  const s = freshStore("add");
  const all = [];
  for (let i = 0; i < 12; i++) {
    const p = makePack(["js116 add " + i + " a", "js116 add " + i + " b"]);
    ingest.land(p.pack, s.shard);
    all.push(p.shas[0], p.shas[1]);
  }
  //  12 equal-size adds violate the ladder after every land; the after-add
  //  hook must keep the stack tiny (un-hooked this accumulates 12 runs).
  const n = runNames(s.shard).length;
  ok(n <= 4, "add: 1/8 ladder held after 12 lands (runs now " + n + ")");
  const r = store.open(s.dir, PROJ);
  for (const sh of all)
    ok(r.getObject(sh), "add: landed object " + sh.slice(0, 8) + " locatable");
  cleanup(s.shard);
}

io.log("idxmaint.js OK\n");
