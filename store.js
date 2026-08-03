//  JS-048: be/lib/store.js — the pure-JS object + ref store, ref read+write.
//  The ref WRITERS (createShard/set/tombstone, folded in from refs.js) sit
//  next to the resolveRef READER in the same module: createShard seeds an
//  empty refs log; set appends a `post` row pinning a bare-40hex sha in the
//  fragment; tombstone appends a `delete` row (zero sha).  Each is read back
//  through store.open(...).resolveRef and must round-trip: set→sha,
//  tombstone→absent.
"use strict";

//  assert.js is a sibling test helper; the JS-ext lib lives in the be/ shard
//  (beagle/test/js → ../../../be/lib).
const { eq, ok } = require("./lib/assert.js");
//  DIS-054: an ISOLATED ticket clone gives the test tree its OWN `.be` shard,
//  so a be-relative `require("shared/store.js")` resolves against THAT
//  (code-less) shard.  Derive the be/ code dir from THIS script's own path
//  (`<be>/test/store.js` → `<be>`); fall back to the be-relative form.
const store = _req("shared/store.js");   // JSQUE-016: lib/ -> shared/
const ulog = _req("shared/ulog.js");
const ingest = _req("shared/ingest.js");   // DOG-027: the keeper.idx family
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}

const SHA = (c) => c.repeat(40);

//  Hermetic store: <dir>/.be/<proj> with a refs log.  store.open(dir, proj)
//  finds <dir>/.be/<proj>; we drive the ref writers directly on the shard path.
const TMP = io.getenv("TMP") || "/tmp";
const dir = TMP + "/js048-store-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
const proj = "p";
const shard = dir + "/.be/" + proj;

//  --- createShard: io.mkdir + seed an empty refs log ---------------------
store.createShard(shard);
ok(io.stat(shard).kind === "dir", "createShard: shard dir exists");
ok(io.stat(shard + "/refs").kind === "reg", "createShard: empty refs seeded");

function resolve(branch) { return store.open(dir, proj).resolveRef(branch); }

//  Fresh shard: trunk is absent.
eq(resolve(""), undefined, "fresh: trunk absent");

//  --- set trunk ----------------------------------------------------------
store.set(shard, "", SHA("a"));
eq(resolve(""), SHA("a"), "set: trunk resolves to the sha");

//  --- set a named branch -------------------------------------------------
store.set(shard, "feat", SHA("b"));
eq(resolve("feat"), SHA("b"), "set: branch resolves to the sha");
eq(resolve(""), SHA("a"), "set: trunk unaffected by the branch set");

//  --- update trunk (latest row wins) -------------------------------------
store.set(shard, "", SHA("c"));
eq(resolve(""), SHA("c"), "set: latest trunk sha wins");

//  --- tombstone trunk → absent ------------------------------------------
store.tombstone(shard, "");
eq(resolve(""), undefined, "tombstone: trunk now absent");
eq(resolve("feat"), SHA("b"), "tombstone: other branch unaffected");

//  --- re-set after a tombstone resurrects the key ------------------------
store.set(shard, "", SHA("d"));
eq(resolve(""), SHA("d"), "set-after-tombstone: trunk resurrected");

//  --- on-disk row vocabulary: verbs post/delete, bare-40hex frag ---------
const verbs = [], frags = [];
ulog.each(shard + "/refs", function (log) {
  verbs.push(log.verb);
  const u = new URI(log.uri);
  frags.push(u.fragment || "");
});
ok(verbs.indexOf("post") >= 0, "rows: a post verb is present");
ok(verbs.indexOf("delete") >= 0, "rows: a delete verb is present");
//  every non-empty fragment is a bare 40-hex sha (no `?` prefix).
for (const f of frags)
  if (f) ok(f.length === 40 && /^[0-9a-f]{40}$/.test(f),
            "rows: fragment is bare 40-hex: " + f);

//  cleanup
for (const f of io.readdir(shard)) { try { io.unlink(shard + "/" + f); } catch (e) {} }

//  --- JS-056: locate() mmaps the on-disk keeper.idx, never re-scans --------
//  Build a hermetic store whose shard holds a real `0000000001.keeper` pack
//  (N blobs) PLUS the prebuilt `<run>.keeper.idx` LSM run the keeper writes.
//  getObject(sha) must resolve a SINGLE object via the mmap'd run — NOT walk
//  the whole pack.  We prove "no O(all-objects) scan" by counting pack.scan
//  calls: the disk-idx path does ZERO; the no-idx fallback does >0.
{
  const sha = _req("shared/util/sha.js");   // JSQUE-016: lib/sha -> shared/util/  (DIS-054 _req: code-shard resolve)
  //  count pack.scan() invocations by wrapping git.pack.mmap (store.js's only
  //  pack opener).  Each opened pack's scan is spied; the counter is global.
  let scans = 0;
  const realMmap = git.pack.mmap;
  git.pack.mmap = function (path, mode, slots) {
    const pk = realMmap(path, mode, slots);
    const realScan = pk.scan;
    pk.scan = function () { scans++; return realScan.apply(this, arguments); };
    return pk;
  };

  const tdir = TMP + "/js056-store-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
  const tproj = "p";
  const tshard = tdir + "/.be/" + tproj;
  io.mkdir(tdir); io.mkdir(tdir + "/.be"); io.mkdir(tshard);

  //  N distinct blobs → one disk pack `0000000001.keeper` (file_id 1).
  const N = 12;
  const FILE_ID = 1;
  const KEEP_FLAGS = 1;                       // KEEP_VAL_FLAGS (pack object)
  const packPath = tshard + "/0000000001.keeper";
  const pk = git.pack.mmap(packPath, "c", 1 << 16);
  pk.header();
  const blobs = [];
  for (let i = 0; i < N; i++) {
    const body = utf8.Encode("js056 object number " + i + " :: " + (i * 2654435761 >>> 0));
    const off = pk.feed("blob", body);
    blobs.push({ body: body, off: off, sha: sha.frameSha("blob", body) });
  }
  pk.finish();
  //  reset the spy counter: building the fixture above is not the unit under
  //  test (and it must NOT be reused as the store's pack mapping).
  scans = 0;

  //  Write the keeper.idx run with the ON-DISK val layout via abc.index:
  //  key = hashlet60<<4 | type(blob=3), val = off<<24 | file_id<<4 | flags.
  //  DOG-027: the run must carry the family MARKER — its 0xF PACK bookmark —
  //  or store.open's audit drops it as incomplete and rebuilds from the pack.
  const run = abc.index("wh128", { dir: tshard, ext: ingest.IDX_EXT });
  for (const b of blobs) {
    const h = sha.hashlet60FromBytes(hex.decode(b.sha));
    const key = (h << 4n) | 3n;              // T_BLOB = 3
    const val = (BigInt(b.off) << 24n) | (BigInt(FILE_ID) << 4n) | BigInt(KEEP_FLAGS);
    run.put(key, val);
  }
  const logBytes = BigInt(io.stat(packPath).size);
  run.put((((12n << 20n) | BigInt(FILE_ID)) << 4n) | 0xfn,
          (BigInt(N) << 32n) | (logBytes - 12n));
  run.commit();                              // persists `<ron64>.keeper.idx`
  ok(run.count === 1, "DOG-027: commit sealed exactly one run");
  ok(ingest.hasMarker(run.run(0)), "DOG-027: the sealed run carries its marker");
  run.close();
  ok(io.readdir(tshard).some((f) => f.endsWith("keeper.idx")),
     "JS-056: keeper.idx run persisted to the shard");

  //  open the store fresh (drops the fixture pack handle) and resolve.
  const r = store.open(tdir, tproj);
  ok(r._diskIndex() != null, "JS-056: store opened the on-disk keeper.idx run");

  //  every object resolves byte-for-byte through the mmap path...
  for (const b of blobs) {
    const obj = r.getObject(b.sha);
    ok(obj && obj.type === "blob", "JS-056: " + b.sha + " resolves as blob");
    eq(obj.bytes.length, b.body.length, "JS-056: " + b.sha + " byte length");
    for (let i = 0; i < b.body.length; i++)
      if (obj.bytes[i] !== b.body[i]) throw "FAIL JS-056 byte " + i + " mismatch";
  }
  //  ...and the pack was NEVER scanned (no O(all-objects) rebuild).  On the
  //  OLD scan-rebuild code this is N>0 — the repro's red assertion.
  eq(scans, 0, "JS-056: getObject via keeper.idx did NOT scan the pack");

  //  --- no-idx FALLBACK still resolves (covers the scan-build path) --------
  //  Fresh shard with a pack but NO keeper.idx run: locate() must fall back to
  //  the in-RAM scan-build and still resolve — and HERE a scan IS expected.
  const fdir = TMP + "/js056-fallback-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
  const fshard = fdir + "/.be/" + tproj;
  io.mkdir(fdir); io.mkdir(fdir + "/.be"); io.mkdir(fshard);
  //  rebuild the same N blobs into the fallback shard's pack (no idx beside it).
  const fpk = git.pack.mmap(fshard + "/0000000001.keeper", "c", 1 << 16);
  fpk.header();
  for (const b of blobs) fpk.feed("blob", b.body);
  fpk.finish();

  scans = 0;
  const fr = store.open(fdir, tproj);
  eq(fr._diskIndex(), null, "JS-056: no-idx shard reports no disk index");
  const fobj = fr.getObject(blobs[0].sha);
  ok(fobj && fobj.type === "blob", "JS-056: fallback resolves via the scan-build");
  ok(scans > 0, "JS-056: the no-idx fallback DID scan the pack (build path)");

  git.pack.mmap = realMmap;                   // restore
  //  cleanup
  for (const d of [tshard, fshard])
    for (const f of io.readdir(d)) { try { io.unlink(d + "/" + f); } catch (e) {} }
}

//  --- DOG-027 marker audit + re-derive ------------------------------------
//  The keeper family's marker IS its 0xF PACK bookmark row.  A run without one
//  is incomplete: openIndex drops it and rebuilds the index from the pack-logs,
//  so the objects stay locatable either way.
{
  const sha = _req("shared/util/sha.js");
  function mkshard(tag) {
    const d = TMP + "/dog027-" + tag + "-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
    const sh = d + "/.be/p";
    io.mkdir(d); io.mkdir(d + "/.be"); io.mkdir(sh);
    const pk = git.pack.mmap(sh + "/0000000001.keeper", "c", 1 << 16);
    pk.header();
    const bs = [];
    for (let i = 0; i < 12; i++) {
      const body = utf8.Encode("dog027 " + tag + " object " + i);
      pk.feed("blob", body);
      bs.push({ body: body, sha: sha.frameSha("blob", body) });
    }
    pk.finish();
    return { dir: d, shard: sh, blobs: bs };
  }
  //  a markerless run: rows committed with no PACK bookmark beside them.
  function plantBogus(shard) {
    const bad = abc.index("wh128", { dir: shard, ext: ingest.IDX_EXT });
    bad.put(0xdeadbeefn << 4n, 7n);
    bad.commit();
    bad.close();
  }

  //  (a) a marked run + a markerless one: only the markerless one goes.
  {
    const f = mkshard("audit");
    ingest.buildIndex(f.shard, "0000000001.keeper", 1);
    plantBogus(f.shard);
    {
      const raw = abc.index("wh128", { dir: f.shard, ext: ingest.IDX_EXT });
      eq(raw.count, 2, "DOG-027: two runs before the audit");
      raw.close();
    }
    const ix = ingest.openIndex(f.shard);
    ok(ix, "DOG-027: the shard still has a usable index after the audit");
    for (let i = 0; i < ix.count; i++)
      ok(ingest.hasMarker(ix.run(i)), "DOG-027: every surviving run is marked");
    eq(ix.get(0xdeadbeefn << 4n), undefined, "DOG-027: the markerless rows are gone");
    ix.close();
    const r = store.open(f.dir, "p");
    for (const b of f.blobs) {
      const o = r.getObject(b.sha);
      ok(o && o.type === "blob", "DOG-027: " + b.sha.slice(0, 8) + " still resolves");
    }
  }

  //  (b) EVERY run markerless: the stack comes up empty and the family
  //      re-derives it from the pack-log.
  {
    const f = mkshard("rederive");
    plantBogus(f.shard);
    const ix = ingest.openIndex(f.shard);
    ok(ix, "DOG-027: a fully markerless stack is re-derived, not left empty");
    ok(ix.count >= 1, "DOG-027: the re-derived run is committed");
    for (let i = 0; i < ix.count; i++)
      ok(ingest.hasMarker(ix.run(i)), "DOG-027: the re-derived run carries its marker");
    eq(ix.get(0xdeadbeefn << 4n), undefined, "DOG-027: the dropped rows did not survive");
    ix.close();
    const r = store.open(f.dir, "p");
    ok(r._diskIndex() != null, "DOG-027: the re-derived index serves the reader");
    for (const b of f.blobs)
      ok(r.getObject(b.sha), "DOG-027: re-derived " + b.sha.slice(0, 8) + " resolves");
  }
}

//  --- DOG-027: fan-out handle lifecycle (the 32-slot pup table) ------------
//  jab's abc.index binding holds PUP_MAX_OPEN(=32) static slots; `work` opens
//  a store per shard, so a reader must RELEASE its keeper.idx slot or shard
//  #33 silently degrades to the in-RAM scan.  40 sequential open+use+close
//  cycles must ALL still get the mmap'd on-disk index.
{
  const sha = _req("shared/util/sha.js");
  const d = TMP + "/dog027-slots-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
  const sh = d + "/.be/p";
  io.mkdir(d); io.mkdir(d + "/.be"); io.mkdir(sh);
  const pk = git.pack.mmap(sh + "/0000000001.keeper", "c", 1 << 16);
  pk.header();
  const body = utf8.Encode("dog027 slots blob");
  pk.feed("blob", body);
  pk.finish();
  const bsha = sha.frameSha("blob", body);
  ingest.buildIndex(sh, "0000000001.keeper", 1);
  for (let i = 0; i < 40; i++) {
    const r = store.open(d, "p");
    ok(r._diskIndex() != null, "DOG-027 cycle " + i + ": got the on-disk index");
    ok(r.getObject(bsha), "DOG-027 cycle " + i + ": the blob resolves");
    r.close();
  }

  //  ...and the DISPATCH shape: a resident session's verbs open readers they
  //  never close themselves; the loop's per-dispatch store.closeAll() sweep
  //  must release every held slot, so the table never fills across verbs.
  for (let i = 0; i < 40; i++) {
    const a = store.open(d, "p"), b = store.open(d, "p");
    ok(a._diskIndex() != null && b._diskIndex() != null,
       "DOG-027 dispatch " + i + ": both readers got the on-disk index");
    ok(a.getObject(bsha) && b.getObject(bsha), "DOG-027 dispatch " + i + ": resolves");
    store.closeAll();
  }

  //  a closed reader SELF-HEALS (re-probes on the next use) and RE-REGISTERS,
  //  so a close is always safe and the sweep keeps covering reused readers.
  {
    const r = store.open(d, "p");
    ok(r._diskIndex() != null, "DOG-027 heal: index open");
    store.closeAll();
    ok(r._diskIndex() != null, "DOG-027 heal: reader re-probes after the sweep");
    for (let i = 0; i < 40; i++) {
      ok(r._diskIndex() != null, "DOG-027 heal " + i + ": reuse stays covered");
      store.closeAll();
    }
  }
}

io.log("store.js OK\n");
