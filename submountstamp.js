//  PUT-012: sub-mount checkout must restamp every materialised file to the
//  sub's TRACK-row assigned ts (GET-049 parity with the root fanout) — else a
//  sub whose checkout lands in the anchor's ms carries the STORE-row ts and can
//  never match the +1 track row, so native status flags the whole sub dirty
//  while JS put/diff read it clean.  Deterministic (asserts stamp==row-ts
//  equality, NOT the same-ms race): drives checkout.apply exactly as
//  submount.mount does — ulog.write the [redirect, track] anchor (capturing the
//  track row's ASSIGNED ts), then checkout.apply — and asserts each materialised
//  file's mtime EQUALS that track ts, symlinks excepted (setMtime follows link).
//  RED before the fix: files carry raw write mtimes; ulog.write returns nothing.
"use strict";

const { eq, ok } = require("./lib/assert.js");
//  DIS-054 isolated-clone require: resolve the modules under test off THIS
//  script's own path so a ticket clone tests ITS code, not the live shard's.
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const checkout = _req("shared/checkout.js");
const ulog     = _req("shared/ulog.js");
const shalib   = _req("shared/util/sha.js");

const TMP = io.getenv("TMP") || "/tmp";
const root = TMP + "/put012-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
io.mkdir(root);

const PIN = "ab".repeat(20), TREE = "cd".repeat(20);
function blobSha(s) { return shalib.frameSha("blob", utf8.Encode(s)); }

//  Minimal keeper stub (statusfast.js storeStub twin): ONE commit -> ONE tree
//  -> the given leaves; getObject maps a leaf sha to its bytes.
function storeStub(leaves) {
  const bySha = {};
  for (const l of leaves) bySha[l.sha] = l.bytes;
  return {
    commitTree: function (sha) { return sha === PIN ? TREE : undefined; },
    readTreeRecursive: function (t, cb) { if (t === TREE) for (const l of leaves) cb(l); },
    getObject: function (sha) { return bySha[sha] ? { bytes: bySha[sha] } : null; }
  };
}
function fleaf(path, content, kind) {
  const bytes = utf8.Encode(content);
  return { path: path, sha: blobSha(content), kind: kind || "f", bytes: bytes };
}

//  --- the mount checkout, deterministic ------------------------------------
//  Model submount.mount's checkout branch step for step: write the sub `.be`
//  anchor [redirect, track] and CAPTURE the track row's assigned ts (row 1),
//  then checkout.apply the pin into the sub wt with that stampTs.  Seed the
//  anchor ts explicitly (a fixed PAST value) so the symlink non-stamp check is
//  race-free: a restamped regular file lands on the past track ts, the symlink
//  keeps its ~now write mtime.
{
  const subWt = root + "/sub";
  io.mkdir(subWt); io.mkdir(subWt + "/.be");
  const anchor = subWt + "/.be";

  //  A fixed past base (2024-ish ron60 via ronStepMs off now, back ~1e9 ms).
  const base = ulog.ronStepMs(ron.now(), -1000000000);
  //  ulog.write assigns row 1 (track) = row 0 (redirect) + 1 on a same-ms
  //  collision; here the explicit ts pins them.  It MUST return the assigned ts.
  const assigned = ulog.write(anchor + "/wtlog",
      [{ verb: "get", uri: "file:" + root + "/store/.be/?/sub", ts: base },
       { verb: "get", uri: "///sub#" + PIN, ts: base + 1n }]);
  ok(assigned && assigned.length === 2, "ulog.write returns the 2 assigned ts");
  const trackTs = assigned[1];
  eq(trackTs, base + 1n, "track row assigned ts is the +1 bumped stamp");

  const leaves = [fleaf(".gitignore", "*.o\n"), fleaf("src/a.c", "int a;\n"),
                  fleaf("run.sh", "#!/bin/sh\n", "x"),
                  fleaf("link", "src/a.c", "l")];   // symlink -> src/a.c
  const co = checkout.apply(storeStub(leaves), PIN, subWt,
                            { force: false, oldTip: "", stampTs: trackTs });
  eq(co.rows.length, 4, "checkout materialised all 4 leaves");

  //  Every regular/exec file's mtime EXACTLY equals the track row ts.
  for (const rel of [".gitignore", "src/a.c", "run.sh"]) {
    const st = io.stat(subWt + "/" + rel);
    eq(st.mtime, trackTs, "materialised " + rel + " mtime == track row ts");
  }
  //  The symlink stays UNSTAMPED (setMtime follows the link) — its lstat mtime
  //  is its ~now write time, never the past track ts.
  const ls = io.lstat(subWt + "/link");
  ok(ls.kind === "lnk", "link materialised as a symlink");
  ok(ls.mtime !== trackTs, "symlink is NOT restamped to the track ts");
}

//  clean exit = ctest GREEN; scrub the scratch.
try { io.rmdir(root, true); } catch (e) {}
function w(s){const u=utf8.Encode(s+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w("PASS submountstamp.js");
