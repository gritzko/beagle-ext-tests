//  PACK-003: ingest.buildIndex vs keeper logs the native header-count-driven
//  pk.scan cannot walk.  The live incident (`jab status` warning
//  `idxmaint: Error: pack.scan: scan (out full? corrupt?)` on EVERY run):
//  a log whose PACK header count exceeds its parseable records — a torn
//  append left a zero tail (the JAB-008 crash window: io.resize survived,
//  the record bytes + msync were lost) — made buildIndex throw forever, so
//  the log stayed unindexed and idxmaint re-warned on every open.
//  (A) torn zero tail, header overcounts  -> buildIndex salvages the
//      parseable records, bookmarks the full extent (no re-attempt churn);
//  (B) verbatim embedded pack (GET-046 keeper-served log: a whole store log
//      with a MID-LOG PACK header) -> the tail walk skips the header and
//      indexes the embedded pack's records instead of silently dropping them;
//  (C) both at once: overcounting header STALLS the native scan ON the
//      embedded header -> the salvage census skips it and indexes both packs.
"use strict";

const { eq, ok } = require("./lib/assert.js");
//  DIS-054: derive the be/ code dir from THIS script's own path (an isolated
//  ticket clone's shard is code-less); fall back to be-relative.
const ingest = _req("shared/ingest.js");
const idxmaint = _req("shared/idxmaint.js");
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

function freshShard(tag) {
  const dir = TMP + "/pack003-" + tag + "-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
  const shard = dir + "/.be/p";
  io.mkdir(dir); io.mkdir(dir + "/.be"); io.mkdir(shard);
  return shard;
}

//  A pack-log byte image [12-byte header | one blob record per text] with the
//  header count == texts.length (the writer's own header(), no trailer).
function makeLog(texts) {
  let cap = 4096;
  for (const t of texts) cap += t.length + 64;
  const ta = new Uint8Array(cap);
  const pk = git.pack.over(ta);
  pk.header();
  for (const t of texts) pk.feed("blob", utf8.Encode(t), -1, null);
  pk.finish();
  return ta.slice(0, Number(pk.buffer.watermark));
}

//  The wh128 key walkTail/scan emit for a blob: (hashlet60 << 4) | type=3.
function blobKey(text) {
  const bytes = utf8.Encode(text);
  const h = shalib.hashlet60FromBytes(hex.decode(shalib.frameSha("blob", bytes)));
  return (h << 4n) | 3n;
}

//  Every non-bookmark key across the shard's runs, as a lookup object.
function runKeys(shard) {
  const keys = {};
  for (const nm of idxmaint.listRuns(shard)) {
    const r = abc.mmap("HEAPwh128", shard + "/" + nm, "r");
    const wm = (r.byteLength / 16) | 0;
    r.buffer.watermark = wm;
    for (let i = 0; i < wm; i++) {
      const k = r[i * 2];
      if ((k & 0xfn) !== 0xfn) keys[k.toString(16)] = true;
    }
    r.buffer._map = null;
  }
  return keys;
}

//  idxmaint's own coverage verdict for fid 1 (the re-attempt predicate).
function coveredBytes(shard) {
  const names = idxmaint.listRuns(shard);
  const views = names.map(function (nm) {
    const r = abc.mmap("HEAPwh128", shard + "/" + nm, "r");
    r.buffer.watermark = (r.byteLength / 16) | 0;
    r._path = shard + "/" + nm;
    return r;
  });
  let cov;
  try { cov = idxmaint.coverage(views); }
  finally { for (const v of views) v.buffer._map = null; }
  return cov ? cov[1] : undefined;
}

function writeLog(shard, u8) {
  ingest.writeBytes(shard + "/0000000001.keeper", u8);
}

//  --- (A) torn zero tail: header count > parseable records ---------------
{
  const shard = freshShard("torn");
  const log = makeLog(["pack003 a1", "pack003 a2", "pack003 a3"]);
  //  the incident shape: the header counts records whose bytes were LOST —
  //  bump count 3 -> 5 and append the torn append's zero tail.
  const torn = new Uint8Array(log.length + 64);      // zeros past the records
  torn.set(log, 0);
  torn[11] = 5;                                      // count u32be low byte
  writeLog(shard, torn);
  let threw = null;
  try { ingest.buildIndex(shard, "0000000001.keeper", 1); }
  catch (e) { threw = "" + e; }
  eq(threw, null, "torn: buildIndex survives a torn zero tail (was: " + threw + ")");
  const keys = runKeys(shard);
  for (const t of ["pack003 a1", "pack003 a2", "pack003 a3"])
    ok(keys[blobKey(t).toString(16)], "torn: salvaged record indexed (" + t + ")");
  const sz = io.stat(shard + "/0000000001.keeper").size;
  ok(coveredBytes(shard) >= sz - 12,
     "torn: run bookmarks the full extent (idxmaint stops re-attempting)");
}

//  --- (B) verbatim embedded pack: mid-log PACK header, honest count ------
{
  const shard = freshShard("embed");
  const logA = makeLog(["pack003 b1", "pack003 b2"]);
  const packB = makeLog(["pack003 b3", "pack003 b4", "pack003 b5"]);
  const both = new Uint8Array(logA.length + packB.length);
  both.set(logA, 0); both.set(packB, logA.length);   // B lands WITH its header
  writeLog(shard, both);
  ingest.buildIndex(shard, "0000000001.keeper", 1);  // scan OK (count = A's 2)
  const keys = runKeys(shard);
  for (const t of ["pack003 b1", "pack003 b2", "pack003 b3", "pack003 b4", "pack003 b5"])
    ok(keys[blobKey(t).toString(16)], "embed: record indexed across the header (" + t + ")");
}

//  --- (C) overcounting header + embedded pack: scan stalls ON the header --
{
  const shard = freshShard("mixed");
  const logA = makeLog(["pack003 c1", "pack003 c2"]);
  const packB = makeLog(["pack003 c3", "pack003 c4"]);
  const both = new Uint8Array(logA.length + packB.length);
  both.set(logA, 0); both.set(packB, logA.length);
  both[11] = 4;                        // header claims 4: record 3 = "PACK..."
  writeLog(shard, both);
  let threw = null;
  try { ingest.buildIndex(shard, "0000000001.keeper", 1); }
  catch (e) { threw = "" + e; }
  eq(threw, null, "mixed: salvage census skips the embedded header (was: " + threw + ")");
  const keys = runKeys(shard);
  for (const t of ["pack003 c1", "pack003 c2", "pack003 c3", "pack003 c4"])
    ok(keys[blobKey(t).toString(16)], "mixed: record indexed (" + t + ")");
  const sz = io.stat(shard + "/0000000001.keeper").size;
  ok(coveredBytes(shard) >= sz - 12, "mixed: full-extent bookmark");
}

//  --- (D) ofs-delta in the walked tail: pk.size is the DELTA's size --------
//  The JS-117 multi-pack shape (header counts the FIRST pack only, appended
//  records behind it).  The tail's ofs-delta record resolves to FAR more than
//  its own pk.size, and the old fixed `io.buf(size*4+256)` out buffer made
//  resolve NOROOM — walkTail silently DROPPED the object (11269 of beagle's
//  28986 salvageable records in the live incident).
{
  const shard = freshShard("delta");
  let base = "pack003 base ";
  while (base.length < 8192) base += "0123456789abcdef ";
  const target = base + " tail-edit";       // near-identical -> tiny delta
  const ta = new Uint8Array(base.length + target.length + 8192);
  const pk = git.pack.over(ta);
  pk.header();
  pk.feed("blob", utf8.Encode(base), -1, null);          // record @12
  pk.feed("blob", utf8.Encode(target), 12, null);        // ofs-delta vs @12
  pk.finish();
  const log = ta.slice(0, Number(pk.buffer.watermark));
  log[11] = 1;                             // header counts the first pack only
  writeLog(shard, log);
  ingest.buildIndex(shard, "0000000001.keeper", 1);      // scan OK, tail walked
  const keys = runKeys(shard);
  ok(keys[blobKey(base).toString(16)], "delta: scanned base indexed");
  ok(keys[blobKey(target).toString(16)],
     "delta: tail ofs-delta object indexed (out buf grows on NOROOM)");
}

io.log("packsalvage.js OK\n");
