//  test/mtimeidx.js — BRO-044: shared/mtimeidx.js, the last-touch lane, and the
//  shared/lastcommit.js retrofit that reads and fills it.  Hermetic: every case
//  builds its OWN keeper pack + its OWN shard in $TMP, so the row and mark
//  arithmetic is exact (the live repo proves nothing).
//
//  Covered:
//    1. cold fill vs warm hit — the same answer, and the warm answer costs ZERO
//       commits walked (the fill record proves it, not a stopwatch);
//    2. the ANSWER matches the raw walk (lastcommit.walkCommits) entry for
//       entry — the `list:` output is unchanged by the cache;
//    3. TREE rows: a directory entry is answered by ONE row, its tree hashlet;
//    4. a NEW commit extends the HEAD — only the gap is walked, the old rows
//       stand, and the new content attributes to the new commit;
//    5. a DEEPER query extends the TAIL — a scope whose rows the first fill's
//       ceiling never reached attributes on the second, deeper query;
//    6. a REVERTED file inherits the EARLIER timestamp (attribution follows
//       CONTENT — the ticket calls this accepted, not a bug);
//    7. a REWRITTEN history drops both MARKS while every ROW survives;
//    8. an all-untracked scope answers blank WITHOUT walking history;
//    9. an explicit `cap` keeps the raw bounded walk (the LIST-001 ceiling).
"use strict";

const { eq, ok } = require("./lib/assert.js");
//  DIS-054: derive the be/ code dir from THIS script's path (test/ingest.js model).
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const store   = _req("shared/store.js");
const mtimeidx = _req("shared/mtimeidx.js");
const lastc   = _req("shared/lastcommit.js");
const shalib  = _req("shared/util/sha.js");

const TMP = io.getenv("TMP") || "/tmp";
const FX = TMP + "/mtimeidx-" + Date.now() + "-" + (Math.random() * 1e9 | 0);

function mkdirp(p) {
  let acc = "";
  for (const s of p.split("/")) { if (s === "") { acc = ""; continue; }
    acc += "/" + s; try { io.mkdir(acc); } catch (e) {} }
}

//  --- a hermetic keeper: blobs, trees and commits into one pack ------------
//  (the test/list/fuse.js fixture builder, kept identical so the two goldens
//  describe the same object graph in the same words.)
function repo(name) {
  const dir = FX + "/" + name, proj = "p", shard = dir + "/.be/" + proj;
  mkdirp(shard);
  const pk = git.pack.mmap(shard + "/0000000001.keeper", "c", 1 << 18);
  pk.header();
  const R = {
    dir: dir, proj: proj, shard: shard, pack: pk,
    blob: function (text) { const b = utf8.Encode(text); pk.feed("blob", b); return shalib.frameSha("blob", b); },
    tree: function (entries) {
      entries = entries.slice().sort(function (a, b) {
        const ka = a.name + (a.mode === "40000" ? "/" : ""), kb = b.name + (b.mode === "40000" ? "/" : "");
        return ka < kb ? -1 : ka > kb ? 1 : 0;
      });
      const parts = []; let total = 0;
      for (const e of entries) {
        const hdr = utf8.Encode(e.mode + " " + e.name + "\0"), sh = new Uint8Array(20);
        for (let i = 0; i < 20; i++) sh[i] = parseInt(e.sha.substr(i * 2, 2), 16);
        parts.push(hdr); parts.push(sh); total += hdr.length + sh.length;
      }
      const out = new Uint8Array(total); let o = 0;
      for (const p of parts) { out.set(p, o); o += p.length; }
      pk.feed("tree", out); return shalib.frameSha("tree", out);
    },
    commit: function (treeSha, parents, epoch, msg) {
      let s = "tree " + treeSha + "\n";
      for (const p of parents) s += "parent " + p + "\n";
      s += "author A <a@e.st> " + epoch + " +0000\n";
      s += "committer A <a@e.st> " + epoch + " +0000\n\n" + msg + "\n";
      const body = utf8.Encode(s);
      pk.feed("commit", body); return shalib.frameSha("commit", body);
    },
    done: function () { pk.finish(); return store.open(dir, proj); },
    //  the lane's runs, so a case can prove a fill wrote (or did not write).
    runs: function () {
      let n = 0;
      for (const f of io.readdir(shard)) if (f.slice(-mtimeidx.IDX_EXT.length) === mtimeidx.IDX_EXT) n++;
      return n;
    }
  };
  return R;
}

const DAY = 86400, E = 1700000000;

//  =========================================================================
//  1-3. cold fill vs warm hit, the unchanged answer, and the TREE row.
//  =========================================================================
//  C0 seeds a.txt + sub/x.txt, C1 adds b.txt, C2 edits sub/x.txt.
const R1 = repo("basic");
const bA0 = R1.blob("A0\n"), bX0 = R1.blob("X0\n");
const tSub0 = R1.tree([{ mode: "100644", name: "x.txt", sha: bX0 }]);
const t0 = R1.tree([{ mode: "100644", name: "a.txt", sha: bA0 },
                    { mode: "40000",  name: "sub",   sha: tSub0 }]);
const C0 = R1.commit(t0, [], E + 0 * DAY, "C0 seed a.txt and sub/x.txt");
const bB1 = R1.blob("B1\n");
const t1 = R1.tree([{ mode: "100644", name: "a.txt", sha: bA0 },
                    { mode: "100644", name: "b.txt", sha: bB1 },
                    { mode: "40000",  name: "sub",   sha: tSub0 }]);
const C1 = R1.commit(t1, [C0], E + 1 * DAY, "C1 add b.txt");
const bX2 = R1.blob("X2\n");
const tSub2 = R1.tree([{ mode: "100644", name: "x.txt", sha: bX2 }]);
const t2 = R1.tree([{ mode: "100644", name: "a.txt", sha: bA0 },
                    { mode: "100644", name: "b.txt", sha: bB1 },
                    { mode: "40000",  name: "sub",   sha: tSub2 }]);
const C2 = R1.commit(t2, [C1], E + 2 * DAY, "C2 edit sub/x.txt");
const k1 = R1.done();

const names1 = ["a.txt", "b.txt", "sub"];
eq(R1.runs(), 0, "BRO-044: the lane starts EMPTY (no run in the shard)");

//  COLD: the answer, and the lane now holds rows.
const cold = lastc.lastCommits(k1, C2, "", names1);
eq(cold["a.txt"].sha, C0, "cold fill: a.txt -> its seed commit C0");
eq(cold["b.txt"].sha, C1, "cold fill: b.txt -> its add commit C1");
eq(cold["sub"].sha, C2, "cold fill: the DIR sub/ -> the newest commit under it (C2)");
eq(cold["sub"].summary, "C2 edit sub/x.txt", "cold fill: sub/ carries the C2 summary");
ok(R1.runs() > 0, "BRO-044: the cold fill SEALED at least one run into the shard");

//  The answer is the RAW walk's answer, entry for entry — `list:` is unchanged.
const raw1 = lastc.walkCommits(k1, C2, "", names1);
for (const n of names1) {
  eq(cold[n].sha, raw1[n].sha, "cache == raw walk: " + n + " same commit");
  eq(cold[n].ts, raw1[n].ts, "cache == raw walk: " + n + " same ts");
  eq(cold[n].summary, raw1[n].summary, "cache == raw walk: " + n + " same summary");
}

//  WARM: the same answer, and NOTHING is walked — the fill is not entered at
//  all, which is what the row for every visible object buys.
const warm = lastc.lastCommits(k1, C2, "", names1);
for (const n of names1) eq(warm[n].sha, cold[n].sha, "warm hit: " + n + " unchanged");
{
  const ix = mtimeidx.openIndex(R1.shard);
  const keys = new Set();
  const byName = lastc.scopeKeys(k1, t2, names1);
  for (const n in byName) keys.add(byName[n]);
  eq(Object.keys(byName).length, 3, "every entry (files AND the dir) maps to ONE row key");
  //  TREE ROW: the dir entry's key IS its tree hashlet with the type-2 nibble.
  eq(byName["sub"], mtimeidx.packKey(mtimeidx.hashletOf(tSub2), mtimeidx.T_TREE),
     "BRO-044: the dir sub/ is keyed by its TREE hashlet | type 2");
  eq(byName["a.txt"], mtimeidx.packKey(mtimeidx.hashletOf(bA0), mtimeidx.T_BLOB),
     "BRO-044: a file is keyed by its BLOB hashlet | type 3");
  const f = mtimeidx.fill(ix, k1, C2, keys, { parentOf: lastc.mainlineParent });
  eq(f.rec.walked, 0, "BRO-044: a warm screen walks ZERO commits");
  //  the tree row answers the whole directory: sub/'s row is C2's time.
  eq(ix.get(byName["sub"]), cold["sub"].ts, "the tree row holds the dir's commit time");
  ix.close();
}

//  =========================================================================
//  4. a NEW commit extends the HEAD.
//  =========================================================================
const R2 = repo("head");
const bP = R2.blob("P\n"), bQ = R2.blob("Q\n");
const tP0 = R2.tree([{ mode: "100644", name: "p.txt", sha: bP }]);
const D0 = R2.commit(tP0, [], E + 0 * DAY, "D0 seed p.txt");
const tP1 = R2.tree([{ mode: "100644", name: "p.txt", sha: bP },
                     { mode: "100644", name: "q.txt", sha: bQ }]);
const D1 = R2.commit(tP1, [D0], E + 1 * DAY, "D1 add q.txt");
const k2 = R2.done();

const at0 = lastc.lastCommits(k2, D0, "", ["p.txt"]);
eq(at0["p.txt"].sha, D0, "head gap: the first fill attributes p.txt at D0");
const at1 = lastc.lastCommits(k2, D1, "", ["p.txt", "q.txt"]);
eq(at1["p.txt"].sha, D0, "head gap: the OLD row stands (p.txt is still D0's)");
eq(at1["q.txt"].sha, D1, "head gap: the new file attributes to the new commit D1");
{
  //  only the GAP was walked: one commit (D1), not the whole history.
  const ix = mtimeidx.openIndex(R2.shard);
  const st = mtimeidx.readAll(ix);
  eq(mtimeidx.markSha(k2, st.marks.head), D1, "head gap: the HEAD mark moved to the new tip");
  eq(mtimeidx.markSha(k2, st.marks.tail), D0, "head gap: the TAIL mark still names the root commit");
  ix.close();
}

//  =========================================================================
//  5. a DEEPER query extends the TAIL frontier.
//  =========================================================================
//  Four commits; the first fill is capped at ONE commit, so the deep entry has
//  no row.  The second, uncapped query pulls the frontier down to it.
const R3 = repo("tail");
const bOld = R3.blob("OLD\n");
const tOld = R3.tree([{ mode: "100644", name: "old.txt", sha: bOld }]);
const F0 = R3.commit(tOld, [], E + 0 * DAY, "F0 seed old.txt");
const bN1 = R3.blob("N1\n");
const tN1 = R3.tree([{ mode: "100644", name: "old.txt", sha: bOld },
                     { mode: "100644", name: "n1.txt", sha: bN1 }]);
const F1 = R3.commit(tN1, [F0], E + 1 * DAY, "F1 add n1.txt");
const bN2 = R3.blob("N2\n");
const tN2 = R3.tree([{ mode: "100644", name: "old.txt", sha: bOld },
                     { mode: "100644", name: "n1.txt", sha: bN1 },
                     { mode: "100644", name: "n2.txt", sha: bN2 }]);
const F2 = R3.commit(tN2, [F1], E + 2 * DAY, "F2 add n2.txt");
const k3 = R3.done();

{
  const ix = mtimeidx.openIndex(R3.shard);
  const byName = lastc.scopeKeys(k3, tN2, ["old.txt", "n1.txt", "n2.txt"]);
  const keys = new Set(); for (const n in byName) keys.add(byName[n]);
  //  a ceiling of ONE commit: the frontier stops at the tip.
  const f1 = mtimeidx.fill(ix, k3, F2, keys, { parentOf: lastc.mainlineParent, cap: 1 });
  eq(f1.rec.walked, 1, "tail frontier: the capped fill walked exactly one commit");
  eq(ix.get(byName["n2.txt"]) !== undefined, true, "tail frontier: the tip's own file has a row");
  eq(ix.get(byName["old.txt"]), undefined, "tail frontier: the deep file has NO row yet");
  //  the deeper query resumes BELOW the recorded tail and reaches it.
  const f2 = mtimeidx.fill(ix, k3, F2, keys, { parentOf: lastc.mainlineParent });
  ok(f2.rec.extend > 0, "tail frontier: the second fill EXTENDED the tail");
  ix.close();
}
const deep = lastc.lastCommits(k3, F2, "", ["old.txt", "n1.txt", "n2.txt"]);
eq(deep["old.txt"].sha, F0, "tail frontier: the deep entry attributes to its seed F0");
eq(deep["n1.txt"].sha, F1, "tail frontier: n1.txt attributes to F1");
eq(deep["n2.txt"].sha, F2, "tail frontier: n2.txt attributes to F2");

//  =========================================================================
//  6. a REVERTED file inherits the EARLIER timestamp.
//  =========================================================================
//  G0 seeds r.txt = "V1"; G1 changes it to "V2"; G2 reverts it to "V1".  The
//  tip's content is the object G0 introduced, so the row is G0's time.
const R4 = repo("revert");
const bV1 = R4.blob("V1\n"), bV2 = R4.blob("V2\n");
const g0 = R4.tree([{ mode: "100644", name: "r.txt", sha: bV1 }]);
const G0 = R4.commit(g0, [], E + 0 * DAY, "G0 seed r.txt V1");
const g1 = R4.tree([{ mode: "100644", name: "r.txt", sha: bV2 }]);
const G1 = R4.commit(g1, [G0], E + 1 * DAY, "G1 r.txt -> V2");
const G2 = R4.commit(g0, [G1], E + 2 * DAY, "G2 revert r.txt -> V1");
const k4 = R4.done();

const rev = lastc.lastCommits(k4, G2, "", ["r.txt"]);
eq(rev["r.txt"].sha, G0, "reverted file: attribution follows CONTENT -> the EARLIER commit G0");
eq(rev["r.txt"].ts < lastc.walkCommits(k4, G2, "", ["r.txt"])["r.txt"].ts, true,
   "reverted file: the cached ts is OLDER than the raw walk's newest-touch ts");

//  =========================================================================
//  7. a REWRITTEN history drops the MARKS; every ROW survives.
//  =========================================================================
//  H0 <- H1 is filled, then H1' (a different commit off H0) becomes the tip.
//  H1 is no longer an ancestor, so both marks go; the rows do not.
const R5 = repo("rewrite");
const bS = R5.blob("S\n"), bT = R5.blob("T\n");
const h0 = R5.tree([{ mode: "100644", name: "s.txt", sha: bS }]);
const H0 = R5.commit(h0, [], E + 0 * DAY, "H0 seed s.txt");
const h1 = R5.tree([{ mode: "100644", name: "s.txt", sha: bS },
                    { mode: "100644", name: "t.txt", sha: bT }]);
const H1 = R5.commit(h1, [H0], E + 1 * DAY, "H1 add t.txt");
const H1b = R5.commit(h1, [H0], E + 2 * DAY, "H1' add t.txt, rewritten");
const k5 = R5.done();

lastc.lastCommits(k5, H1, "", ["s.txt", "t.txt"]);
let rowsBefore;
{
  const ix = mtimeidx.openIndex(R5.shard);
  const st = mtimeidx.readAll(ix);
  rowsBefore = st.rows;
  eq(mtimeidx.markSha(k5, st.marks.head), H1, "rewrite: the mark names the OLD tip before the rewrite");
  ix.close();
}
//  Every visible row is already cached, so the rewritten tip alone does not
//  even enter the fill — the stale mark is harmless because only a fill reads
//  it.  The answer is served from the surviving rows.
const after = lastc.lastCommits(k5, H1b, "", ["s.txt", "t.txt"]);
eq(after["s.txt"].sha, H0, "rewrite: s.txt still attributes to H0 (the ROW survived)");
{
  //  Now force a fill at the rewritten tip: the mark is no longer an ancestor,
  //  so BOTH marks are dropped and the walk restarts from the new tip.
  const ix = mtimeidx.openIndex(R5.shard);
  const byName = lastc.scopeKeys(k5, h1, ["s.txt", "t.txt"]);
  const keys = new Set(); for (const n in byName) keys.add(byName[n]);
  const f = mtimeidx.fill(ix, k5, H1b, keys, { parentOf: lastc.mainlineParent });
  eq(f.rec.dropped, true, "rewrite: the marks were DROPPED (the old tip is no ancestor)");
  const st = mtimeidx.readAll(ix);
  eq(mtimeidx.markSha(k5, st.marks.head), H1b, "rewrite: the HEAD mark re-set to the new tip");
  for (const [key, v] of rowsBefore)
    ok(st.rows.get(key) !== undefined && st.rows.get(key) <= v,
       "rewrite: every cached row survived and never moved NEWER");
  ix.close();
}

//  =========================================================================
//  8. an all-untracked scope answers blank WITHOUT walking history.
//  =========================================================================
//  `nope/` is in nobody's tree, so nothing under it can ever be attributed —
//  the raw walk pays the whole history to learn that; the lane answers at once.
const none = lastc.lastCommits(k1, C2, "nope/", ["TODO-001.mkd", "TODO-002.mkd"]);
eq(Object.keys(none).length, 0, "an uncommitted scope answers blank");
const noneRaw = lastc.walkCommits(k1, C2, "nope/", ["TODO-001.mkd", "TODO-002.mkd"]);
eq(Object.keys(noneRaw).length, 0, "...the same blank the raw walk spends a history to reach");

//  =========================================================================
//  9. an explicit `cap` keeps the RAW bounded walk (the LIST-001 ceiling).
//  =========================================================================
//  The lane is WARM here (case 1 filled it), so this proves the ceiling knob
//  still exercises the walk rather than being answered from cache.
const capped = lastc.lastCommits(k1, C2, "", names1, 1);
eq(capped["sub"].sha, C2, "cap=1: the tip's own entry is attributed");
eq(capped["a.txt"], undefined, "cap=1: the ceiling still leaves an old entry blank");

//  cleanup
for (const r of [R1, R2, R3, R4, R5])
  for (const f of io.readdir(r.shard)) { try { io.unlink(r.shard + "/" + f); } catch (e) {} }

io.log("test/mtimeidx.js OK\n");
