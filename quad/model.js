//  test/quad/model.js — BRO-030: the unified quad status model
//  (shared/quad.js) against wiki/Status.mkd's table.  A mocked keeper
//  serves a small DAG (R ← B1 base side; R ← T1 ← T2 track side) with
//  per-commit trees; the wt axis is injected as classify-shaped rows.
//  Pins: the four relations per column, wt mirrors base when clean,
//  staged/con flags, the commit-row quads (".o.." local, "o..." miss,
//  "o.o." absorbed — STATUS-012), track-less and broken-tree edges, and
//  the renderer's plain + colored row shapes.
"use strict";

const { eq, ok } = require("../lib/assert.js");

function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const quad = _req("shared/quad.js");
const quadrender = _req("view/quadrender.js");

//  --- fixture DAG + trees ------------------------------------------------
const R  = "0d".repeat(20);          // root (LCA)
const B1 = "b1".repeat(20);          // base tip   (R ← B1)
const T1 = "71".repeat(20);          // track side (R ← T1 ← T2)
const T2 = "72".repeat(20);
const X9 = "e9".repeat(20);          // disjoint-history tip (broken tree)

const A0 = "a0".repeat(20), A2 = "a2".repeat(20);
const B0 = "b0".repeat(20), BX = "bb".repeat(20);
const D0 = "d0".repeat(20), G0 = "90".repeat(20);
const S0 = "50".repeat(20), TN = "7e".repeat(20);

const PARENTS = {};
PARENTS[R] = []; PARENTS[B1] = [R]; PARENTS[T1] = [R]; PARENTS[T2] = [T1];
PARENTS[X9] = [];

//  path → sha per commit; `s` is removed on the track side, `t` created.
const TREES = {};
TREES[R]  = { a: A0, b: B0, d: D0, g: G0, s: S0 };
TREES[B1] = { a: A0, b: BX, d: D0, g: G0, s: S0 };
TREES[T1] = { a: "a1".repeat(20), b: B0, d: D0, g: G0, s: S0 };
TREES[T2] = { a: A2, b: B0, d: D0, g: G0, t: TN };
TREES[X9] = { z: "99".repeat(20) };

const EPOCH = { }; EPOCH[R] = 1700000000; EPOCH[B1] = 1700000400;
EPOCH[T1] = 1700000100; EPOCH[T2] = 1700000200; EPOCH[X9] = 1700000300;

const k = {
  commitTree: function (sha) { return TREES[sha] ? "tree/" + sha : undefined; },
  readTreeRecursive: function (treeSha, cb) {
    const t = TREES[treeSha.slice(5)] || {};
    for (const p of Object.keys(t).sort())
      cb({ path: p, sha: t[p], kind: "f", mode: 0o100644 });
  },
  commitParents: function (sha) { return PARENTS[sha] || []; },
  parseCommit: function (sha) {
    return { author: "A <a@a> " + (EPOCH[sha] || 0) + " +0000",
             body: "c-" + sha.slice(0, 2) };
  },
};

function rowsByPath(m) {
  const o = {};
  for (const r of m.rows) o[r.path] = r;
  return o;
}

//  --- leg 1: file-row quads, no patch ------------------------------------
const wtRows = [
  { bucket: "mod", path: "d", ts: 7n },            // wt edit        → ...↑
  { bucket: "unk", path: "e", ts: 8n },            // untracked      → ...+
  { bucket: "del", path: "g", ts: 9n },            // staged delete  → ...X bold
];
let m = quad.quadModel({ k: k, base: B1, track: T2, patches: [], wtRows: wtRows });
eq(m.root, R, "root is the LCA of track and base");
let by = rowsByPath(m);
eq(by.a.quad, "v...", "theirs-side change pending sync");
eq(by.b.quad, ".v..", "committed base change: wt is CLEAN vs base (local-dirt axis)");
eq(by.d.quad, "...v", "mod: wt-only advance");
eq(by.e.quad, "...o", "unk: wt-only create");
eq(by.g.quad, "...x", "del: wt-only removal");
ok(by.g.staged && !by.d.staged, "staged rides the del row, not the mod row");
eq(by.s.quad, "x...", "track removed the path");
eq(by.t.quad, "o...", "track created the path");
ok(!by.c, "an all-same path earns no row");

//  commit rows: base-side ".o..", track-side "o..." (newest-first per side).
const cq = {};
for (const c of m.commits) cq[c.sha] = c;
eq(cq[B1].quad, ".o..", "local unposted commit");
eq(cq[T2].quad, "o...", "unabsorbed track commit");
eq(cq[T1].quad, "o...", "unabsorbed track commit (deep)");
ok(cq[T2].subject === "c-72", "commit row carries the subject");

//  --- leg 2: an absorbed line is patch-column ground (STATUS-012) --------
m = quad.quadModel({ k: k, base: B1, track: T2, patches: [T2], wtRows: [
  { bucket: "pat", path: "a", ts: 4n },            // theirs landed in the wt
  { bucket: "con", path: "b", ts: 5n },            // weave conflict
] });
by = rowsByPath(m);
eq(by.a.quad, "v.vv", "pat: track, patch and wt columns advance");
ok(by.b.con, "con flag rides the conflicted row");
eq(by.b.quad[3], "v", "conflicted wt reads advanced");
eq(by.t.quad, "o.o.", "theirs-created path shows in the patch column");
const cq2 = {};
for (const c of m.commits) cq2[c.sha] = c;
eq(cq2[T2].quad, "o.o.", "absorbed commit gains the patch '+' (STATUS-012)");
eq(cq2[T1].quad, "o.o.", "the whole absorbed line gains the patch '+'");
eq(cq2[B1].quad, ".o..", "local commit untouched by the patch column");

//  --- leg 3: degenerate roots -------------------------------------------
m = quad.quadModel({ k: k, base: B1, track: "", patches: [],
                     wtRows: [{ bucket: "mod", path: "d", ts: 1n }] });
eq(m.rows.length, 1, "track-less: only the wt dirt earns rows");
eq(m.rows[0].quad, "...v", "track-less: track column mirrors base (all '.')");
let threw = "";
try { quad.quadModel({ k: k, base: B1, track: X9, patches: [], wtRows: [] }); }
catch (e) { threw = String(e); }
ok(threw.indexOf("broken tree") >= 0, "no common ancestor refuses loudly");

//  --- leg 4: renderer ----------------------------------------------------
m = quad.quadModel({ k: k, base: B1, track: T2, patches: [], wtRows: wtRows });
const plain = quadrender.renderModel(m, { color: false });
ok(plain.some(function (l) { return / \.\.\.X g$/.test(l); }),
   "plain file row is `<date> <quad> <path>`");
ok(plain.some(function (l) { return l.indexOf(" .o.. ?" + B1.slice(0, 8) + "#c-b1") >= 0; }),
   "plain commit row is `<date> <quad> ?<hashlet>#<subject>`");
const colored = quadrender.renderModel(m, { color: true });
ok(colored.some(function (l) { return l.indexOf("\x1b[38;2;255;255;255;48;2;255;140;0m") >= 0; }),
   "staged wt char inverts: white on orange");
ok(colored.join("").indexOf("\x1b[38;2;30;144;255m") >= 0,
   "track glyph paints blue");
ok(colored.join("").indexOf("∅") >= 0 && colored.join("").indexOf("●") >= 0,
   "tty glyphs: removed is ∅, created is ●");
ok(colored.some(function (l) { return l.indexOf("✔") >= 0 && l.indexOf(" ?") >= 0; }),
   "commit rows render presence as ✔");
//  a conflicted row paints the wt char white on dark red
const mc = quad.quadModel({ k: k, base: B1, track: T2, patches: [T2],
  wtRows: [{ bucket: "con", path: "b", ts: 5n }] });
const cl = quadrender.renderModel(mc, { color: true }).join("");
ok(cl.indexOf("\x1b[38;2;255;255;255;48;2;220;40;40m") >= 0, "conflicted wt char is white on dark red");
