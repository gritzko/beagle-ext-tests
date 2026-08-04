//  GIT-021: store.getObject must not re-run the delta chase to size its out
//  buffer.  `pk.size` on an OFS-delta record is the DELTA STREAM's size, not
//  the resolved object's (PACK-003), so the old `io.buf(pk.size + 64)` +
//  double-and-retry ladder NOROOM'd ~11 times per delta object and threw the
//  whole buffer away each round: a linux-v3.0 checkout burned 64 646 retries
//  and 848 MB of transient buffers over 36 783 leaves (anon RSS 48 MB ->
//  1.8 GB).  The fixture below is that shape at 200 objects: one big base
//  blob plus a chain of tiny OFS deltas that each resolve back to ~400 KB.
//  Instrument: wrap io.buf and count what a read loop allocates.
"use strict";

const { eq, ok, bytesEq } = require("./lib/assert.js");
const ingest = _req("shared/ingest.js");
const store  = _req("shared/store.js");
const sha    = _req("shared/util/sha.js");
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}

const TMP = io.getenv("TMP") || "/tmp";
const N = 200;                 // delta records in the chain
const BODY = 400 * 1024;       // resolved object size — each delta stream is tiny

//  --- fixture: a base blob + N tiny OFS deltas off it ---------------------
function body(seed) {
  const b = new Uint8Array(BODY);
  let x = (seed * 2654435761) >>> 0;
  for (let i = 0; i < BODY; i++) { x = (x * 1103515245 + 12345) >>> 0; b[i] = (x >> 16) & 0xff; }
  return b;
}
const base = body(1);
const ta = new Uint8Array((N + 4) * 64 * 1024 + BODY * 4);
const pk = git.pack.over(ta);
pk.header();
const want = [];
const baseOff = pk.feed("blob", base, -1, null);
want.push({ sha: sha.frameSha("blob", base), len: base.length });
for (let i = 0; i < N; i++) {
  //  a one-byte edit off the SAME base: the delta stream is a few dozen bytes,
  //  the resolved object stays BODY bytes — the PACK-003 size trap.
  const v = base.slice();
  v[i * 97 % BODY] = (i + 1) & 0xff;
  pk.feed("blob", v, baseOff, null);
  want.push({ sha: sha.frameSha("blob", v), len: v.length });
}
pk.finish();
const wm = Number(pk.buffer.watermark);
const full = new Uint8Array(wm + 20);
full.set(ta.subarray(0, wm), 0);
full.set(sha1(ta.subarray(0, wm)), wm);

const dir = TMP + "/git021-resolve-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
const shard = dir + "/.be/p";
io.mkdir(dir); io.mkdir(dir + "/.be"); io.mkdir(shard);
ingest.land(full, shard);

//  the delta records ARE tiny — pin the trap the ladder fell into
{
  const p = git.pack.mmap(shard + "/0000000001.keeper", "r");
  p.buffer.watermark = p.byteLength;
  ok(p.seek(baseOff), "fixture: base record seeks");
  eq(p.size, BODY, "fixture: the base record declares the full object size");
  let deltas = 0, biggest = 0;
  p.rewind();
  while (p.next()) if (p.type === "ofs-delta") { deltas++;
    if (p.size > biggest) biggest = p.size; }
  eq(deltas, N, "fixture: every non-base record is an OFS delta");
  ok(biggest < BODY / 8, "fixture: a delta stream is far smaller than its object" +
     " (" + biggest + " vs " + BODY + ")");
}

//  --- the read loop, with io.buf instrumented ----------------------------
const r = store.open(dir, "p");
r.getObject(want[0].sha);                      // warm: index open + first size

const realBuf = io.buf;
let bufs = 0, bufBytes = 0;
io.buf = function (n) { bufs++; bufBytes += n; return realBuf(n); };
let read = 0;
try {
  for (const w of want) {
    const o = r.getObject(w.sha);
    ok(o && o.type === "blob", "read: " + w.sha + " comes back as a blob");
    eq(o.bytes.length, w.len, "read: full resolved length");
    read++;
  }
} finally { io.buf = realBuf; }
eq(read, N + 1, "read: every object resolved");

//  correctness, byte-for-byte, on a re-read through the SAME reader (the
//  shared resolve buffer must not leak one object's bytes into the next)
{
  const a = r.getObject(want[0].sha), b = r.getObject(want[N].sha);
  const a2 = r.getObject(want[0].sha);
  bytesEq(a.bytes, a2.bytes, "re-read: the shared buffer does not poison a re-read");
  ok(a.bytes[0] !== undefined && b.bytes.length === BODY, "re-read: both full length");
}

//  THE ASSERTION.  Resolving N+1 objects of BODY bytes needs ONE buffer that
//  grows to ~BODY.  The old ladder allocated one per NOROOM round per object.
const objBytes = (N + 1) * BODY;
io.log("GIT-021: " + (N + 1) + " reads allocated " + bufs + " buffers / " +
       (bufBytes / 1048576).toFixed(1) + " MB (object bytes " +
       (objBytes / 1048576).toFixed(1) + " MB)\n");
ok(bufs <= 8, "resolve allocates a handful of buffers, not one ladder per read" +
   " (got " + bufs + ")");
ok(bufBytes < objBytes / 4, "resolve does not allocate a multiple of the object" +
   " bytes (got " + (bufBytes / 1048576).toFixed(1) + " MB for " +
   (objBytes / 1048576).toFixed(1) + " MB of objects)");

//  A record offset the pack rejects reports absent — it must NOT climb the
//  ladder to 1 GB first (PTR-010: a failed seek unpositions the cursor).
{
  let bufs2 = 0;
  io.buf = function (n) { bufs2++; return realBuf(n); };
  let miss;
  try { miss = r._locate("0".repeat(40)); } finally { io.buf = realBuf; }
  eq(miss, undefined, "a sha that is not in the shard locates to nothing");
}

io.log("store_resolve OK\n");
