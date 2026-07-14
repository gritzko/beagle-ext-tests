//  GET-044: wire.js STREAMS the incoming pack to a `tmp_pack_*` file in the
//  destination shard (bounded RSS) instead of buffering the whole pack in the
//  heap (the old readToEof chunks[]+concat, which RangeError'd at linux scale);
//  ingest.clone/land then VERIFY the 20-byte sha1 trailer off an mmap and land
//  the log by atomic rename, dropping the trailer.  Abort = unlink, store
//  untouched.  Hermetic: a real (>64KiB) pack fed through a file fd — no net.
"use strict";

const { eq, ok, throws } = require("./lib/assert.js");
const wire   = _req("shared/wire.js");
const ingest = _req("shared/ingest.js");
const store  = _req("shared/store.js");
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}

const TMP = io.getenv("TMP") || "/tmp";
function freshDir(tag) {
  const dir = TMP + "/get044-" + tag + "-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
  io.mkdir(dir);
  return dir;
}

//  A REAL git packfile of one big blob (>64KiB, so a full-buffer reader would
//  allocate pack-sized while the streamer caps at a 64KiB scratch) + the git
//  20-byte sha1(body) trailer (wire.emitPack / test/ingest.js recipe).
function makePack(body) {
  const ta = new Uint8Array(body.length + 4096);
  const pk = git.pack.over(ta);
  pk.header();
  pk.feed("blob", body, -1, null);
  pk.finish();
  const wm = Number(pk.buffer.watermark);
  const full = new Uint8Array(wm + 20);
  full.set(ta.subarray(0, wm), 0);
  full.set(sha1(ta.subarray(0, wm)), wm);
  return { pack: full, blobSha: shaOfBlob(body) };
}
function shaOfBlob(body) {
  const hdr = utf8.Encode("blob " + body.length + "\0");
  const b = io.buf(hdr.length + body.length); b.feed(hdr); b.feed(body);
  return hex.encode(sha1(b.data()));
}

//  Write bytes to a file and hand back its read fd (stands in for the wire
//  socket the spawn path drains — io._read hits EOF at the file end).
function fileFd(bytes) {
  const p = freshDir("src") + "/incoming";
  const w = io.open(p, "c"); io.writeAll(w, bytes); io.close(w);
  return io.open(p, "r");
}

//  INCOMPRESSIBLE 200 KiB (LCG bytes) so the zlib'd pack still exceeds 64KiB.
const BIG = (function () {
  const n = 200 * 1024, u = new Uint8Array(n);
  let s = 0x1234567 | 0;                        // xorshift32 (32-bit exact in JS)
  for (let i = 0; i < n; i++) {
    s ^= s << 13; s ^= s >>> 17; s ^= s << 5; u[i] = s & 0xff;
  }
  return u;
})();
const mk = makePack(BIG);
ok(mk.pack.length > (1 << 16), "fixture pack exceeds the 64KiB scratch");

//  --- (1) drainToFile: streams the raw pack to a tmp file in destDir --------
{
  const dest = freshDir("dest");
  const fd = fileFd(mk.pack);
  const r = wire.drainToFile(fd, new Uint8Array(0), dest);
  io.close(fd);
  ok(r && r.packFile, "drainToFile returns a packFile path");
  ok(r.verified === true, "drainToFile stream-verified the trailer (flag set)");
  ok(r.packFile.indexOf(dest) === 0, "tmp pack lands INSIDE destDir (same FS)");
  ok(r.packFile.indexOf("tmp_pack_") >= 0, "tmp file is a tmp_pack_*");
  eq(r.packLen, mk.pack.length, "packLen == streamed byte count (incl trailer)");
  const got = io.mmap(r.packFile, "r").data();
  eq(hex.encode(sha1(got.subarray(0, r.packLen))),
     hex.encode(sha1(mk.pack)), "on-disk tmp bytes are byte-identical");
  try { io.unlink(r.packFile); } catch (e) {}
}

//  --- (2) drainToFile prepends the already-buffered pkt head ----------------
{
  const dest = freshDir("dest2");
  const head = mk.pack.subarray(0, 100);
  const fd = fileFd(mk.pack.subarray(100));
  const r = wire.drainToFile(fd, head, dest);
  io.close(fd);
  eq(r.packLen, mk.pack.length, "head + tail == whole pack");
  const got = io.mmap(r.packFile, "r").data();
  eq(hex.encode(sha1(got.subarray(0, r.packLen))),
     hex.encode(sha1(mk.pack)), "head-prefixed stream reassembles the pack");
  try { io.unlink(r.packFile); } catch (e) {}
}

//  --- (3) ingest.clone from a streamed {packFile} descriptor ---------------
//  Verifies the trailer, renames into 0000000001.keeper (trailer dropped),
//  builds the index; the store then reads the blob back.
{
  const dest = freshDir("clone");
  const fd = fileFd(mk.pack);
  const r = wire.drainToFile(fd, new Uint8Array(0), dest);
  io.close(fd);
  ingest.clone({ packFile: r.packFile, packLen: r.packLen },
               dest + "/.be", "p", "0".repeat(40), "be:/x?/p");
  const log = dest + "/.be/p/0000000001.keeper";
  eq(io.size(io.open(log, "r")) + 20, mk.pack.length,
     "landed keeper log == pack MINUS the 20-byte trailer");
  ok(!exists(r.packFile), "streamed tmp file renamed away (not left behind)");
  const k = store.open(dest + "/.be", "p");
  const obj = k.getObject(mk.blobSha);
  ok(obj && obj.bytes.length === BIG.length, "blob reads back from the clone");
}

//  --- (4) a CORRUPT trailer is refused AT EOF; the tmp is unlinked (abort) --
//  GET-044: drainToFile hashes AS THE BYTES STREAM (20-byte lag) and verifies
//  the trailer at EOF — no mmap (the 31-bit map cap), no post-hoc re-read.
{
  const dest = freshDir("bad");
  const bad = mk.pack.slice();
  bad[bad.length - 1] ^= 0xff;                 // flip a trailer byte
  const fd = fileFd(bad);
  throws(function () { wire.drainToFile(fd, new Uint8Array(0), dest); },
         "drainToFile refuses a bad sha1 trailer at EOF");
  io.close(fd);
  const left = io.readdir(dest).filter(function (n) { return n.indexOf("tmp_pack_") === 0; });
  eq(left.length, 0, "the rejected tmp pack is unlinked (store untouched)");
}

//  --- (5) ingest refuses an UNVERIFIED corrupt file descriptor too ----------
{
  const dest = freshDir("bad2");
  const bad = mk.pack.slice();
  bad[100] ^= 0xff;                            // flip a body byte
  const p = dest + "/tmp_pack_x";
  const w = io.open(p, "c"); io.writeAll(w, bad); io.close(w);
  throws(function () {
    ingest.clone({ packFile: p, packLen: bad.length },   // no verified flag
                 dest + "/.be", "p", "0".repeat(40), "be:/x?/p");
  }, "clone map-verifies an unverified file source");
  ok(!exists(p), "the rejected tmp pack is unlinked");
  ok(!exists(dest + "/.be/p/0000000001.keeper"), "no keeper log landed on refuse");
}

//  --- (5b) a verified:true descriptor SKIPS the map re-verify ---------------
//  (the >2GB path cannot map at all — prove the skip by landing a pack whose
//  TRAILER is wrong: map-verify would refuse it, the verified flag skips it;
//  wire.drainToFile is the sole producer of verified:true).
{
  const dest = freshDir("skip");
  const bad = mk.pack.slice();
  bad[bad.length - 1] ^= 0xff;                 // trailer byte, body scannable
  const p = dest + "/tmp_pack_y";
  const w = io.open(p, "c"); io.writeAll(w, bad); io.close(w);
  ingest.clone({ packFile: p, packLen: bad.length, verified: true },
               dest + "/.be", "p", "0".repeat(40), "be:/x?/p");
  ok(exists(dest + "/.be/p/0000000001.keeper"),
     "verified descriptor lands without a map re-hash");
}

//  --- (6) the streaming hasher (sha1s) matches the native one-shot sha1 -----
{
  const sha1s = _req("shared/util/sha1s.js");
  for (const n of [0, 1, 55, 56, 63, 64, 65, 128, 100000]) {
    const d = BIG.subarray(0, n);
    const h = sha1s.open();
    //  feed in ragged splits to cross block boundaries
    let o = 0, step = 7;
    while (o < n) { const t = Math.min(n - o, step); h.feed(d.subarray(o, o + t)); o += t; step = (step * 3 + 1) % 61 + 1; }
    eq(hex.encode(h.close()), hex.encode(sha1(d)), "sha1s == sha1 @ " + n);
  }
}

function exists(p) { try { io.stat(p); return true; } catch (e) { return false; } }

io.log("PASS be-js-unit-wire_stream");
