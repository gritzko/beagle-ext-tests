//  STATUS-011: status re-hashes every clean tracked file — classifyMerge must
//  take the wtlog mtime-stamp fast path (the SAME stamp-set stage.js:150/242
//  trusts): an in-base+on-disk file whose wt mtime ∈ wtlog.has(ts) is clean
//  (`ok`) with NO content read (io.open).  Membership test only — status stays
//  read-only (no re-stamp; DIS-023 banned the re-stamping drift gate, not this).
//  RED before the fix: scenario A observes one io.open per clean stamped file;
//  GREEN after: zero.  Scenario B pins byte-parity on stamp-MISS paths (content
//  still read, buckets unchanged) + the stamp-collision trust (accepted risk).
//  Scenario C pins DIS-057 precedence: a patch-band stamp (cnf == the patch row
//  ts, which IS in the stamp-set) still routes con/mrg, NEVER collapses to ok.
"use strict";

const { eq, ok } = require("./lib/assert.js");
//  DIS-054 isolated-clone require: derive the be/ code dir from this script's
//  own path (`<be>/test/statusfast.js` → `<be>`), fall back to be-relative.
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const classify = _req("shared/classify.js");
const wtlog = _req("shared/wtlog.js");
const ulog = _req("shared/ulog.js");
const shalib = _req("shared/util/sha.js");

const TMP = io.getenv("TMP") || "/tmp";
const root = TMP + "/status011-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
io.mkdir(root);

const COMMIT = "ab".repeat(20), TREE = "cd".repeat(20), THEIRS = "5e".repeat(20);

function writeF(p, s) {
  const u = utf8.Encode(s); const b = io.buf(u.length + 8); b.feed(u);
  const fd = io.open(p, "c"); io.writeAll(fd, b); io.close(fd);
}
function blobSha(s) { return shalib.frameSha("blob", utf8.Encode(s)); }

//  Minimal store stub: ONE commit → ONE tree → the given leaves (classifyMerge
//  reads nothing else); an unknown sha (e.g. a patch THEIRS pin) resolves null.
function storeStub(leaves) {
  return {
    commitTree: function (sha) { return sha === COMMIT ? TREE : undefined; },
    readTreeRecursive: function (t, cb) { if (t === TREE) for (const l of leaves) cb(l); }
  };
}
function leaf(path, content) {
  return { path: path, sha: blobSha(content), kind: "f", mode: 0o100644 };
}

//  Build one scratch wt: files on disk, a REAL wtlog (`get ?master#<commit>`
//  [+ a patch row]), and the baseline stub.  Returns { be, wtl, k, getTs, ... }.
function mkwt(name, rows) {
  const wt = root + "/" + name;
  io.mkdir(wt); io.mkdir(wt + "/.be");
  ulog.write(wt + "/.be/wtlog", rows);
  const wtl = wtlog.open({ bePath: wt + "/.be/wtlog", project: "" });
  return { wt: wt, wtl: wtl };
}

//  io.open hook: count content opens during ONE classify run (wtEqBase reads
//  via io.open; wtlog/ignore/gitmodules read via abc.mmap/io.mmap, not here).
const realOpen = io.open;
let opens = 0;
function counted(fn) {
  opens = 0;
  io.open = function () { opens++; return realOpen.apply(io, arguments); };
  try { return fn(); } finally { io.open = realOpen; }
}

//  --- A. the perf repro: all tracked files clean + get-stamped ------------
//  N files, bytes == baseline, every mtime stamped to the get row ts (the
//  restamp post/put/patch perform).  status must bucket all `ok` with ZERO
//  per-file content reads — RED before the fix (opens == N), GREEN after.
{
  const A = mkwt("A", [{ verb: "get", uri: "?master#" + COMMIT }]);
  const files = { "a.txt": "alpha\n", "b.txt": "bravo\n", "c.txt": "charlie\n",
                  "d.txt": "delta\n", "sub/e.txt": "echo\n" };
  io.mkdir(A.wt + "/sub");
  const leaves = [];
  for (const rel in files) { writeF(A.wt + "/" + rel, files[rel]); leaves.push(leaf(rel, files[rel])); }
  const getTs = A.wtl.rows[0].ts;
  for (const rel in files) io.setMtime(A.wt + "/" + rel, getTs);
  const res = counted(function () {
    return classify.classify({ wt: A.wt }, A.wtl, storeStub(leaves));
  });
  eq(res.counts.ok, 5, "A: all 5 clean stamped files bucket ok");
  eq(res.rows.length, 0, "A: status emits no rows for a clean wt");
  eq(res.counts.mod, 0, "A: no false mod");
  eq(opens, 0, "A: zero per-file content reads (io.open) on the stamp fast path");
}

//  --- B. stamp-MISS byte-parity + bucket correctness ----------------------
//  A non-stamp mtime still pays the content read and buckets by content truth;
//  a stamp-COLLIDING mtime over edited bytes reads clean (the accepted risk /
//  trust stage.js:150 already extends — and the fast path's other RED signal).
{
  const B = mkwt("B", [{ verb: "get", uri: "?master#" + COMMIT }]);
  const leaves = [leaf("clean.txt", "same\n"), leaf("edited.txt", "old\n"),
                  leaf("collide.txt", "committed\n"), leaf("gone.txt", "bye\n")];
  //  a write can land in the SAME ms as the just-sampled get row ts (an mtime
  //  is ms-packed ron60), so the stamp-MISS mtimes are pinned explicitly.
  const miss = ulog.ronStepMs(B.wtl.rows[0].ts, -3);        // ∉ the stamp-set
  writeF(B.wt + "/clean.txt", "same\n");        // clean, non-stamp mtime
  writeF(B.wt + "/edited.txt", "new\n");        // edited, non-stamp mtime → mod
  writeF(B.wt + "/collide.txt", "EDITED\n");    // edited, mtime forced onto the stamp
  writeF(B.wt + "/untracked.txt", "loose\n");   // not in base → unk
  io.setMtime(B.wt + "/clean.txt", miss);
  io.setMtime(B.wt + "/edited.txt", miss);
  io.setMtime(B.wt + "/collide.txt", B.wtl.rows[0].ts);
  const res = counted(function () {
    return classify.classify({ wt: B.wt }, B.wtl, storeStub(leaves));
  });
  eq(res.counts.ok, 2, "B: clean(content-confirmed) + collide(stamp-trusted) are ok");
  eq(res.counts.mod, 1, "B: the edited non-stamp file stays mod");
  eq(res.counts.unk, 1, "B: untracked is unk");
  eq(res.counts.mis, 1, "B: base-only gone.txt is mis");
  eq(opens, 2, "B: stamp-miss paths still content-read (clean.txt + edited.txt)");
  const buckets = {};
  for (const r of res.rows) buckets[r.path] = r.bucket;
  eq(buckets["edited.txt"], "mod", "B: mod row for edited.txt");
  eq(buckets["untracked.txt"], "unk", "B: unk row for untracked.txt");
  eq(buckets["gone.txt"], "mis", "B: mis row for gone.txt");
}

//  --- C. DIS-057 patch-band precedence over the fast path ------------------
//  The `cnf` band slot IS the patch row ts — a wtlog stamp-set member.  The
//  pStamp axis must route con/mrg BEFORE the stamp fast path, never ok.
{
  const C = mkwt("C", [{ verb: "get", uri: "?master#" + COMMIT },
                       { verb: "patch", uri: "#" + THEIRS }]);
  const P = C.wtl.rows[1].ts;                    // patch row ts = band ceiling
  const leaves = [leaf("conf.txt", "base\n"), leaf("merged.txt", "base\n")];
  writeF(C.wt + "/conf.txt", "THEIRS<<<\n");     // modified vs ours-base
  writeF(C.wt + "/merged.txt", "woven\n");
  io.setMtime(C.wt + "/conf.txt", P);                       // cnf slot (∈ stamp-set)
  io.setMtime(C.wt + "/merged.txt", ulog.ronStepMs(P, -1)); // mrg slot
  const res = counted(function () {
    return classify.classify({ wt: C.wt }, C.wtl, storeStub(leaves));
  });
  const buckets = {};
  for (const r of res.rows) buckets[r.path] = r.bucket;
  eq(buckets["conf.txt"], "con", "C: cnf band stamp routes con, never fast-path ok");
  eq(buckets["merged.txt"], "mrg", "C: mrg band stamp routes mrg");
  eq(res.counts.ok, 0, "C: no band-stamped file collapses to ok");
}

//  clean exit = ctest GREEN; scrub the scratch.
try { io.rmdir(root, true); } catch (e) {}
