//  DIS-057 (REOPENED 2026-06-29): the patch stamp band must survive the
//  filesystem mtime round-trip.  The patch verb stamps each merged file's
//  mtime to a ron60 in a 3-stamp band (pat/mrg/cnf) and classify reads the
//  band back; if a band stamp is not a VALID ron60 it stamps as epoch-0 and
//  the read misses → the file falls through to `mod` (the headline `pat`
//  regression).  ron60 is NOT a linear count: its low 12 bits are a PACKED
//  ms field (0-999), so a raw BigInt `base+1n`/`base+2n` that pushes ms to
//  >=1000 is an INVALID ron60 (RONToTime rejects → FILESetMtime writes 0).
//  This exercises the band at every ms/ss/mm boundary against the REAL
//  ulog.ronStepMs (the ms-correct stepper) + classify.patchStamps (the band
//  reader) + a live io.setMtime/io.lstat round-trip.  RED before the fix:
//  raw `+n` overflows at ms in {998,999} and the band lookup misses.
"use strict";

const { eq, ok, fail } = require("./lib/assert.js");

//  DIS-054 isolated-clone require: derive the be/ code dir from this script's
//  own path (`<be>/test/patchband.js` → `<be>`), fall back to be-relative.
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const ulog = _req("shared/ulog.js");
const classify = _req("shared/classify.js");

//  decode the packed ms field (ulog layout: low 12 bits = [1]*64 + [0], 0-999).
function msField(r) {
  r = BigInt(r);
  const d = (k) => Number((r >> BigInt(k * 6)) & 63n);
  return d(1) * 64 + d(0);
}
//  craft a ron60 at 2026-06-29 12:mm:ss.lll with an explicit ms field.
function craft(msval, ss, mm) {
  ss = ss || 0; mm = mm || 0;
  let r = 0n; const set = (k, x) => { r |= (BigInt(x) & 63n) << BigInt(k * 6); };
  set(9, 2); set(8, 6); set(7, 6); set(6, 2); set(5, 9);
  set(4, 12); set(3, mm); set(2, ss);
  set(1, Math.floor(msval / 64)); set(0, msval % 64);
  return r;
}

ok(typeof ulog.ronStepMs === "function", "ulog.ronStepMs must exist (ms-correct ron60 stepper)");
ok(typeof classify.patchStamps === "function", "classify.patchStamps must be exported for testing");

const TMP = io.getenv("TMP") || "/tmp";
const dir = TMP + "/dis057-patchband-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
io.mkdir(dir);
const f = dir + "/f.txt";
io.close(io.open(f, "c"));

//  --- (a) the stepper yields VALID, FS-round-trip-stable ron60 -----------
//  Every band stamp must be a valid ron60 (ms<1000) AND survive setMtime→lstat.
for (const bm of [0, 500, 997, 998, 999]) {
  for (const ss of [0, 30, 59]) {
    const base = craft(bm, ss, 59);
    const ceil = ulog.ronStepMs(base, 2);                 // patch-row ts = band ceiling
    const stamps = { pat: base, mrg: ulog.ronStepMs(base, 1), cnf: ceil };
    for (const k in stamps) {
      const v = stamps[k];
      ok(msField(v) < 1000, "band " + k + " (bm=" + bm + ",ss=" + ss + ") not a valid ron60 ms=" + msField(v));
      io.setMtime(f, v);
      eq(io.lstat(f).mtime, v, "FS round-trip " + k + " bm=" + bm + " ss=" + ss);
    }
    //  the ceiling reconstructs the band downward (what patchStamps does).
    eq(ulog.ronStepMs(ceil, -2), base, "ronStepMs invertible (-2) bm=" + bm + " ss=" + ss);
    eq(ulog.ronStepMs(ceil, -1), stamps.mrg, "ronStepMs invertible (-1) bm=" + bm + " ss=" + ss);
  }
}

//  --- (b) end-to-end band: stamp like patch.js, read like classify -------
//  For each outcome, stamp the wt file to its band slot, persist a `patch`
//  row at the ceiling, then assert classify.patchStamps[wt-mtime] == bucket.
function bandHit(base, slot /* "pat"|"mrg"|"cnf" */) {
  const ceil = ulog.ronStepMs(base, 2);
  const stamp = slot === "pat" ? base
              : slot === "mrg" ? ulog.ronStepMs(base, 1)
              : ceil;
  io.setMtime(f, stamp);
  const wtTs = io.lstat(f).mtime;
  //  minimal wtlog reader stub: ONE in-scope patch row at the ceiling.
  const reader = { rows: [{ verb: "patch", ts: ceil }], patchFloor: function () { return null; } };
  const band = classify.patchStamps(reader);
  return band[wtTs.toString()];
}
for (const bm of [0, 100, 998, 999]) {
  for (const ss of [0, 59]) {
    const base = craft(bm, ss, 59);
    eq(bandHit(base, "pat"), "pat", "pat band miss at bm=" + bm + " ss=" + ss);
    eq(bandHit(base, "mrg"), "mrg", "mrg band miss at bm=" + bm + " ss=" + ss);
    eq(bandHit(base, "cnf"), "cnf", "cnf band miss at bm=" + bm + " ss=" + ss);
  }
}

print_ok();
function print_ok() { /* a clean exit (no throw) is ctest GREEN */ }
