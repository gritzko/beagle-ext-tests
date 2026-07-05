//  test/list/fuse.js — LIST-001 repro: the `list:` view fuses ls's wt marker
//  with each entry's LAST COMMIT (summary + age) via a BOUNDED first-touch walk.
//
//  A `jab list:` that ONLY listed the wt (like ls) would drop the per-entry
//  commit context.  This builds a hermetic keeper (N files + a subdir over M
//  commits), drives shared/lastcommit.lastCommits + view/render.relAge +
//  views/list/list.js's hunk builders, and asserts:
//    RED  (no fuse): entries carry no last-commit summary/age; a dir gets none.
//    GREEN (fused): each file → its FIRST-TOUCH (newest) commit summary+ts; a
//                   DIR → the newest commit touching anything UNDER it; relAge
//                   renders a short `Nh`/`Nd`/`Ny`; the row toks carry the wt
//                   marker slot + a hidden `U` name click-target + a grey summary.

"use strict";

const { eq, ok } = require("../lib/assert.js");
const store  = require("shared/store.js");
const lastc  = require("shared/lastcommit.js");
const render = require("view/render.js");
const theme  = require("view/theme.js");
const list   = require("views/list/list.js");
const sha    = require("shared/util/sha.js");

const TMP = io.getenv("TMP") || "/tmp";
const dir = TMP + "/list001-fuse-" + Date.now() + "-" + (Math.random() * 1e9 | 0);
const proj = "p";
const shard = dir + "/.be/" + proj;
io.mkdir(dir); io.mkdir(dir + "/.be"); io.mkdir(shard);

//  --- fixture: blobs + trees + commits into ONE keeper pack ---------------
const pk = git.pack.mmap(shard + "/0000000001.keeper", "c", 1 << 16);
pk.header();
function hexToBytes(h) { const b = new Uint8Array(20); for (let i = 0; i < 20; i++) b[i] = parseInt(h.substr(i * 2, 2), 16); return b; }
function blob(text) { const b = utf8.Encode(text); pk.feed("blob", b); return sha.frameSha("blob", b); }
//  git tree: sorted `<mode> <name>\0<20-byte-sha>` records.  A tree name sorts
//  as if a dir carried a trailing '/', so we sort on that key (git's rule).
function tree(entries) {
  entries = entries.slice().sort(function (a, b) {
    const ka = a.name + (a.mode === "40000" ? "/" : ""), kb = b.name + (b.mode === "40000" ? "/" : "");
    return ka < kb ? -1 : ka > kb ? 1 : 0;
  });
  const parts = []; let total = 0;
  for (const e of entries) {
    const hdr = utf8.Encode(e.mode + " " + e.name + "\0"), sh = hexToBytes(e.sha);
    parts.push(hdr); parts.push(sh); total += hdr.length + sh.length;
  }
  const out = new Uint8Array(total); let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  pk.feed("tree", out); return sha.frameSha("tree", out);
}
function commit(treeSha, parents, epoch, msg) {
  let s = "tree " + treeSha + "\n";
  for (const p of parents) s += "parent " + p + "\n";
  s += "author A <a@e.st> " + epoch + " +0000\n";
  s += "committer A <a@e.st> " + epoch + " +0000\n\n" + msg + "\n";
  const body = utf8.Encode(s);
  pk.feed("commit", body); return sha.frameSha("commit", body);
}

//  Realistic epochs so commitTs orders them; ~24h apart so relAge reads in days.
const DAY = 86400, E = 1700000000;
//  C0: a.txt seeded + sub/x.txt seeded.
const bA0 = blob("A0\n"), bX0 = blob("X0\n");
const tSub0 = tree([{ mode: "100644", name: "x.txt", sha: bX0 }]);
const t0 = tree([{ mode: "100644", name: "a.txt", sha: bA0 },
                 { mode: "40000",  name: "sub",   sha: tSub0 }]);
const C0 = commit(t0, [], E + 0 * DAY, "C0 seed a.txt and sub/x.txt");
//  C1: b.txt ADDED (a.txt + sub unchanged).
const bB1 = blob("B1\n");
const t1 = tree([{ mode: "100644", name: "a.txt", sha: bA0 },
                 { mode: "100644", name: "b.txt", sha: bB1 },
                 { mode: "40000",  name: "sub",   sha: tSub0 }]);
const C1 = commit(t1, [C0], E + 1 * DAY, "C1 add b.txt");
//  C2: sub/x.txt EDITED (a.txt + b.txt unchanged) — the newest touch UNDER sub/.
const bX2 = blob("X2\n");
const tSub2 = tree([{ mode: "100644", name: "x.txt", sha: bX2 }]);
const t2 = tree([{ mode: "100644", name: "a.txt", sha: bA0 },
                 { mode: "100644", name: "b.txt", sha: bB1 },
                 { mode: "40000",  name: "sub",   sha: tSub2 }]);
const C2 = commit(t2, [C1], E + 2 * DAY, "C2 edit sub/x.txt");
pk.finish();

const k = store.open(dir, proj);
ok(k.parseCommit(C2), "fixture: tip C2 reads back as a commit");

//  --- the fuse: last-commit attribution over the immediate entries --------
const names = ["a.txt", "b.txt", "sub"];
const cm = lastc.lastCommits(k, C2, "", names);

//  a.txt: first touched at C0 (seed) — never changed since, so its LAST commit
//  walking back is C0.  b.txt: added at C1.  sub: newest touch under it is C2.
eq(cm["a.txt"].sha, C0, "LIST-001: a.txt attributed its seed commit C0");
eq(cm["a.txt"].summary, "C0 seed a.txt and sub/x.txt", "a.txt carries C0 summary");
eq(cm["b.txt"].sha, C1, "LIST-001: b.txt attributed its add commit C1");
eq(cm["b.txt"].summary, "C1 add b.txt", "b.txt carries C1 summary");
//  THE DIR REPRO: sub/ = the NEWEST commit touching anything beneath it (C2),
//  NOT its own seed (C0).  A no-fuse listing would give sub/ no commit at all.
eq(cm["sub"].sha, C2, "LIST-001: dir sub/ = newest commit under it (C2)");
eq(cm["sub"].summary, "C2 edit sub/x.txt", "sub/ carries the C2 summary");

//  ts ordering: a.txt(C0) < b.txt(C1) < sub(C2).
ok(cm["a.txt"].ts < cm["b.txt"].ts && cm["b.txt"].ts < cm["sub"].ts,
   "attributed ts increase C0<C1<C2");

//  --- relAge boundaries (the render.js sibling of dateCol) -----------------
function ageOf(deltaSec) {
  const now = ron.of((E + deltaSec) * 1000), ts = ron.of(E * 1000);
  return render.relAge(ts, now);
}
eq(render.relAge(0n, ron.now()), "", "relAge: ts==0 → blank");
eq(ageOf(30), "30s", "relAge: 30s");
eq(ageOf(90), "1m", "relAge: 90s → 1m");
eq(ageOf(3 * 3600), "3h", "relAge: 3h (ticket example)");
eq(ageOf(2 * DAY), "2d", "relAge: 2d (ticket example)");
eq(ageOf(400 * DAY), "1y", "relAge: >1y (ticket example)");

//  --- the fused ROW: marker slot + name U-target + grey summary + age ------
//  appendRow(textParts, spans, off, marker, name, navUri, summary, age).
function rowTags(marker, name, nav, summary, age) {
  const textParts = [], spans = [];
  const n = list.appendRow(textParts, spans, 0, marker, name, nav, summary, age);
  //  reconstruct the row bytes + the tag letters, in order.
  let total = 0; for (const p of textParts) total += p.length;
  const body = new Uint8Array(total); let o = 0;
  for (const p of textParts) { body.set(p, o); o += p.length; }
  const tags = spans.map(function (s) { return typeof s[0] === "number" ? s[0] : s[0]; });
  return { body: body, tags: tags, len: n };
}
function tagCode(letter) { return letter.charCodeAt(0) - 65; }
const TAG_U = tagCode("U"), TAG_D = tagCode("D"), TAG_F = tagCode("F");

//  A modified file row: the marker is the wt bucket `mod` → its VERB_SLOT tag.
const modSlot = tagCode(theme.VERB_SLOT["mod"]);   // 'E'
const r = rowTags("mod", "a.txt", "cat a.txt", "C0 seed a.txt and sub/x.txt", "2d");
ok(r.tags.indexOf(modSlot) >= 0, "LIST-001: row carries the wt marker palette slot");
ok(r.tags.indexOf(TAG_U) >= 0, "LIST-001: row carries a hidden U name click-target");
ok(r.tags.indexOf(TAG_F) >= 0, "LIST-001: row carries the F (name) token");
ok(r.tags.indexOf(TAG_D) >= 0, "LIST-001: row carries the grey (D) summary slot");
//  The visible bytes contain the name, the summary, the age, and the hidden nav.
const rowStr = utf8.Decode ? utf8.Decode(r.body) : String.fromCharCode.apply(null, r.body);
ok(rowStr.indexOf("a.txt") >= 0, "row shows the name");
ok(rowStr.indexOf("C0 seed") >= 0, "row shows the pale summary");
ok(rowStr.indexOf("2d") >= 0, "row shows the rel-age");
ok(rowStr.indexOf("cat a.txt") >= 0, "row carries the hidden nav spell");

//  --- bound: a tight ceiling leaves an old entry unattributed (blank) ------
//  cap=1 walks ONLY the tip C2 → only sub/ is attributed; a.txt/b.txt blank.
const capped = lastc.lastCommits(k, C2, "", names, 1);
eq(capped["sub"].sha, C2, "cap=1: sub/ (touched at the tip) attributed");
eq(capped["a.txt"], undefined, "LIST-001: ceiling leaves an old entry blank");

//  cleanup
for (const f of io.readdir(shard)) { try { io.unlink(shard + "/" + f); } catch (e) {} }

io.log("test/list/fuse.js OK\n");
