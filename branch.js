//  SUBS-050: shared/branch.js — the ONE parsed-branch codec.  All three
//  recorded shapes (absolute / relative-dotted / plain) must parse → format /
//  key round-trip; sub() must compose the synthetic-branch chain (byte-for-byte
//  the retired submount.syntheticBranch output); wireRef/fromWireRef must map
//  trunk ↔ `refs/heads/main` and strip the title.
"use strict";

const { eq, ok } = require("./lib/assert.js");
//  DIS-054: resolve the module under test off THIS script's own path first,
//  so an isolated ticket clone tests ITS code, not the live shard's.
function _req(mod) {
  const self = (typeof process !== "undefined" && process.argv && process.argv[1]) || "";
  if (self) {
    const d = self.slice(0, self.lastIndexOf("/test/"));
    if (d && d !== self) { try { return require(d + "/" + mod); } catch (e) {} }
  }
  return require(mod);
}
const branch = _req("shared/branch.js");

//  --- parse: the three recorded shapes -------------------------------------
//  plain / trunk (a primary wt).
eq(JSON.stringify(branch.parse("JS-101", "proj").branch), '["JS-101"]', "plain segs");
eq(branch.parse("JS-101", "proj").title, "proj", "plain title = passed");
eq(JSON.stringify(branch.parse("", "proj").branch), "[]", "trunk segs");
ok(branch.isTrunk(branch.parse("", "proj")), "trunk isTrunk");
ok(!branch.isTrunk(branch.parse("JS-101", "proj")), "branch !isTrunk");

//  absolute: title from the head, dotted chain follows.
eq(branch.parse("/libdog/.jab/JS-101", "ignored").title, "libdog", "abs title = head");
eq(JSON.stringify(branch.parse("/libdog/.jab/JS-101", "x").branch),
   '[".jab","JS-101"]', "abs chain segs");

//  relative-dotted: re-headed with the passed title, dots kept on the segments.
eq(branch.parse(".libdog/.jab/JS-101", "libabc").title, "libabc", "rel re-headed title");
eq(JSON.stringify(branch.parse(".libdog/.jab/JS-101", "libabc").branch),
   '[".libdog",".jab","JS-101"]', "rel keeps dots");

//  a leading `?` is tolerated.
eq(JSON.stringify(branch.parse("?JS-101", "p").branch), '["JS-101"]', "leading ? shed");

//  --- format: the ONE canonical shape --------------------------------------
eq(branch.format(branch.parse("JS-101", "proj")), "JS-101", "format plain");
eq(branch.format(branch.parse("", "proj")), "", "format trunk");
//  every shape of a mounted sub formats to the SAME absolute label.
eq(branch.format(branch.parse("/libdog/.jab/JS-101", "x")), "/libdog/.jab/JS-101",
   "format sub from absolute");
eq(branch.format(branch.parse(".jab/JS-101", "libdog")), "/libdog/.jab/JS-101",
   "format sub from relative re-heads with own title");
//  sub-of-sub: absolute, with ITS OWN title head — no bare-dotted relative leak.
eq(branch.format(branch.parse(".libdog/.jab/JS-101", "libabc")),
   "/libabc/.libdog/.jab/JS-101", "format sub-of-sub absolute w/ own title");

//  --- key: title-stripped relative bytes (byte-identical to legacy rows) ----
eq(branch.key(branch.parse("JS-101", "p")), "JS-101", "key plain");
eq(branch.key(branch.parse("", "p")), "", "key trunk");
eq(branch.key(branch.parse("/libdog/.jab/JS-101", "x")), ".jab/JS-101", "key from absolute");
eq(branch.key(branch.parse(".libdog/.jab/JS-101", "libabc")), ".libdog/.jab/JS-101",
   "key from relative");
//  legacy DOGQueryStripProject parity: strip the head segment of an abs query.
function legacyStrip(q) {
  if (!q || q[0] !== "/") return q || "";
  const j = q.indexOf("/", 1);
  return j < 0 ? "" : q.slice(j + 1);
}
for (const q of ["", "JS-101", "/proj/JS-101", "/libdog/.jab/JS-101",
                 ".libdog/.jab/JS-101", "/proj", "/proj/br&abc"])
  eq(branch.key(branch.parse(q, "t")), legacyStrip(q), "key == legacyStrip(" + q + ")");

//  --- sub: the synthetic-branch chain (retired syntheticBranch strings) -----
function syn(title, pt, pb) {
  return branch.format(branch.sub(branch.parse(pb || "", pt || "parent"), title));
}
eq(syn("libdog", "jab", ""), "/libdog/.jab", "sub of a trunk parent");
eq(syn("libdog", "jab", "JS-107"), "/libdog/.jab/JS-107", "sub of a branched parent");
eq(syn("libabc", "libdog", "/libdog/.jab"), "/libabc/.libdog/.jab",
   "nested sub folds the parent's synthetic branch");
eq(syn("x", "libabc", "/libabc/.libdog/.jab"), "/x/.libabc/.libdog/.jab",
   "third level keeps folding the chain");
eq(syn("libabc", "libdog", "/libdog/.jab/JS-107"), "/libabc/.libdog/.jab/JS-107",
   "the gp_branch stays the last undotted segment");

//  --- wireRef / fromWireRef: trunk ↔ main, title-stripped ------------------
eq(branch.wireRef(branch.parse("", "p")), "refs/heads/main", "wireRef trunk → main");
eq(branch.wireRef(branch.parse("feature", "p")), "refs/heads/feature", "wireRef named");
eq(branch.wireRef(branch.parse("/libdog/.jab/JS", "x")), "refs/heads/.jab/JS",
   "wireRef strips the title head");
eq(branch.key(branch.fromWireRef("refs/heads/main", "p")), "", "fromWireRef main → trunk");
eq(branch.key(branch.fromWireRef("refs/heads/feature", "p")), "feature",
   "fromWireRef named");
//  wireRef ∘ fromWireRef round-trips the key.
for (const k of ["", "feature", ".jab/JS-101"]) {
  const br = branch.fromWireRef("refs/heads/" + (k || "main"), "t");
  eq(branch.key(br), k, "wire round-trip key " + JSON.stringify(k));
}

//  --- display -------------------------------------------------------------
eq(branch.display(branch.parse("JS-101", "p")), "?JS-101", "display plain");
eq(branch.display(branch.parse("/libdog/.jab/JS-101", "x")), "?/libdog/.jab/JS-101",
   "display sub");

function w(s){const u=utf8.Encode(s+"\n");const b=io.buf(u.length+8);b.feed(u);io.write(1,b);}
w("PASS branch.js");
